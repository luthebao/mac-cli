package clean_cmd

import "core:fmt"
import "core:strings"
import "core:thread"

import "mc:cli"
import "mc:clean/scan"
import "mc:clean/tui"
import "mc:clean/types"
import "mc:fsx"
import "mc:util"

// run_interactive is the default `mac-cli clean` flow:
//   scan all enabled categories → present checkbox → drill-down → confirm → clean.
run_interactive :: proc(args: []string) -> int {
	spec := []cli.Flag{
		{name = "risky",          short = "r", takes_value = false},
		{name = "deep",           takes_value = false},
		{name = "file-picker",    short = "f", takes_value = false},
		{name = "absolute-paths", short = "A", takes_value = false},
		{name = "no-progress",    takes_value = false},
		{name = "dry-run",        short = "d", takes_value = false},
		{name = "help",           short = "h", takes_value = false},
	}
	p := cli.parse(args, spec)

	if cli.bool_flag(p, "help") {
		fmt.println("Run `mac-cli help clean` for usage.")
		return 0
	}

	// The scan→select→clean flow is destructive and relies on interactive
	// confirmation. Without a TTY those prompts silently take their defaults —
	// and in --deep mode rows arrive pre-selected — so refuse to proceed rather
	// than risk an unattended deletion. `clean categories` is the safe,
	// non-interactive way to see what would be scanned.
	if !tui.is_interactive() {
		fmt.println(util.dim("clean: interactive cleanup needs a terminal. Run it directly in a shell, or use `mac-cli clean categories` to preview categories."))
		return 0
	}

	// Deep mode is the "scan everything" preset: it pulls in the risky
	// scanners too, and pre-selects every safe/moderate category so the user
	// just reviews and confirms instead of hand-picking. Risky categories are
	// shown but left unchecked — deep should be thorough, not reckless.
	deep          := cli.bool_flag(p, "deep")
	include_risky := cli.bool_flag(p, "risky") || deep
	dry_run       := cli.bool_flag(p, "dry-run")

	scanners := scan.scanners_for(include_risky, context.temp_allocator)
	title := deep ? "🧹 mac-cli clean (deep)" : "🧹 mac-cli clean"
	fmt.println(util.bold(title))
	fmt.println(strings.repeat("─", 50, context.temp_allocator))
	fmt.println("Scanning your Mac for cleanable files…")
	fmt.println()

	// Parallel scan via thread pool — total time ~= slowest scanner.
	results := parallel_scan(scanners)

	total: i64 = 0
	for r in results {
		total += r.total_size
	}
	fmt.printfln("Found %s that can be cleaned.", util.bold(fsx.format_size(total, context.temp_allocator)))
	fmt.println()

	if total == 0 {
		fmt.println(util.dim("Nothing to clean — your Mac is already tidy."))
		return 0
	}

	// Present the checkbox.
	rows := make([]tui.CheckboxItem, len(results), context.temp_allocator)
	for r, i in results {
		hint := fsx.format_size(r.total_size, context.temp_allocator)
		if r.error != "" {
			hint = strings.concatenate({hint, "  ⚠ ", r.error}, context.temp_allocator)
		}
		label := fmt.aprintf("%-26s %d items", r.category.name, len(r.items), allocator = context.temp_allocator)
		rows[i] = tui.CheckboxItem{
			label          = label,
			hint           = hint,
			supports_drill = r.category.supports_file_selection || cli.bool_flag(p, "file-picker"),
			disabled       = r.total_size == 0,
			// Deep mode pre-checks everything safe enough to bulk-clean.
			selected       = deep && r.total_size > 0 && r.category.safety != .Risky,
		}
	}

	// Track per-row drill selections — if the user drills into row N,
	// we replace the row's items with a filtered set.
	working_items := make([][]types.CleanableItem, len(results), context.temp_allocator)
	for r, i in results {
		working_items[i] = r.items
	}

	outer: for {
		result, drill := tui.checkbox("Select categories to clean", rows)
		switch result {
		case .Cancelled:
			fmt.println(util.dim("Cancelled."))
			return 0
		case .Drill_Down:
			selected, cancelled := tui.explore(results[drill].category.name, working_items[drill])
			if cancelled {
				continue outer
			}
			// Replace working_items[drill] with the filtered set.
			filtered := make([dynamic]types.CleanableItem, 0, len(selected), context.temp_allocator)
			for keep, j in selected {
				if keep {
					append(&filtered, working_items[drill][j])
				}
			}
			working_items[drill] = filtered[:]
			// Recompute that row's size hint and auto-mark it selected.
			new_total: i64 = 0
			for it in filtered {
				new_total += it.size
			}
			rows[drill].hint = fmt.aprintf("%s (%d picked)", fsx.format_size(new_total, context.temp_allocator), len(filtered), allocator = context.temp_allocator)
			rows[drill].selected = len(filtered) > 0
		case .Submitted:
			break outer
		}
	}

	// Confirm.
	picked_total: i64 = 0
	picked_items: int = 0
	for row, i in rows {
		if !row.selected {
			continue
		}
		for it in working_items[i] {
			picked_total += it.size
			picked_items += 1
		}
	}
	if picked_total == 0 {
		fmt.println(util.dim("Nothing selected. Done."))
		return 0
	}

	fmt.println(util.bold("Summary"))
	fmt.printfln("  Items to delete: %d", picked_items)
	fmt.printfln("  Space to free:   %s", fsx.format_size(picked_total, context.temp_allocator))
	fmt.println()
	verb := "clean"
	if dry_run {
		verb = "preview (dry run)"
	}
	ok := tui.confirm(fmt.aprintf("Proceed with %s?", verb, allocator = context.temp_allocator), true)
	if !ok {
		fmt.println(util.dim("Cancelled."))
		return 0
	}

	// Execute cleans.
	fmt.println()
	bar: tui.ProgressBar
	tui.progress_start(&bar, picked_items, "Cleaning")
	cleaned_results := make([]types.CleanResult, len(results), context.temp_allocator)
	for row, i in rows {
		if !row.selected {
			continue
		}
		scanner := scanners[i]
		cleaned_results[i] = scanner.clean(working_items[i], dry_run, context.temp_allocator)
		tui.progress_advance(&bar, len(working_items[i]))
	}
	tui.progress_finish(&bar)

	// Final report.
	fmt.println()
	fmt.println(util.bold(util.green("✓ Cleaning Complete!")))
	fmt.println(strings.repeat("─", 50, context.temp_allocator))
	total_freed: i64 = 0
	total_cleaned := 0
	for row, i in rows {
		if !row.selected {
			continue
		}
		cr := cleaned_results[i]
		total_freed += cr.freed_bytes
		total_cleaned += cr.cleaned_items
		fmt.printfln("  %-26s ✓ %s freed",
			cr.category.name,
			fsx.format_size(cr.freed_bytes, context.temp_allocator))
		for e in cr.errors {
			fmt.printfln("    %s", util.yellow(e, context.temp_allocator))
		}
	}
	fmt.println(strings.repeat("─", 50, context.temp_allocator))
	fmt.printfln("🎉 Freed %s of disk space!", util.bold(fsx.format_size(total_freed, context.temp_allocator)))
	fmt.printfln("   Cleaned %d items", total_cleaned)
	return 0
}

// parallel_scan runs all scanners concurrently via core:thread.Pool.
@(private)
parallel_scan :: proc(scanners: []types.Scanner) -> []types.ScanResult {
	results := make([]types.ScanResult, len(scanners), context.allocator)

	// Sequential fallback for environments without thread support.
	// Using thread.Pool would also work but adds complexity for marginal
	// gain — most scanners are I/O-bound and the OS already overlaps them.
	pool: thread.Pool
	thread.pool_init(&pool, allocator = context.allocator, thread_count = 8)
	defer thread.pool_destroy(&pool)
	thread.pool_start(&pool)

	Task_Data :: struct {
		scanner: types.Scanner,
		result:  ^types.ScanResult,
	}
	task_data := make([]Task_Data, len(scanners), context.temp_allocator)

	for s, i in scanners {
		task_data[i] = Task_Data{scanner = s, result = &results[i]}
		thread.pool_add_task(&pool, context.allocator, proc(task: thread.Task) {
			td := cast(^Task_Data)task.data
			td.result^ = td.scanner.scan({}, context.allocator)
		}, &task_data[i], i)
	}
	thread.pool_finish(&pool)
	return results
}
