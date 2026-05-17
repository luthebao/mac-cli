package clean_cmd

import "core:fmt"
import "core:os"
import "core:strings"

import "mc:cli"
import "mc:clean/tui"
import "mc:fsx"
import "mc:util"

// run_uninstall lists apps in /Applications, lets the user pick which to
// fully remove (app bundle + its preferences, caches, support, etc.).
run_uninstall :: proc(args: []string) -> int {
	spec := []cli.Flag{
		{name = "yes",     short = "y", takes_value = false},
		{name = "dry-run", short = "d", takes_value = false},
		{name = "help",    short = "h", takes_value = false},
	}
	p := cli.parse(args, spec)

	if cli.bool_flag(p, "help") {
		fmt.println(
`mac-cli clean uninstall — remove apps and their leftovers

USAGE
  mac-cli clean uninstall [--yes] [--dry-run]

OPTIONS
  --yes      Skip confirmation prompts
  --dry-run  Show what would be removed; don't actually remove
`)
		return 0
	}

	dry_run := cli.bool_flag(p, "dry-run")
	yes     := cli.bool_flag(p, "yes")

	// Build app list from /Applications.
	apps, err := os.read_directory_by_path("/Applications", -1, context.temp_allocator)
	if err != nil {
		fmt.eprintln("uninstall: cannot read /Applications:", err)
		return 1
	}

	rows := make([dynamic]tui.CheckboxItem, 0, len(apps), context.temp_allocator)
	app_paths := make([dynamic]string, 0, len(apps), context.temp_allocator)
	for a in apps {
		if !strings.has_suffix(a.name, ".app") {
			continue
		}
		size, _ := fsx.dir_size(a.fullpath)
		append(&rows, tui.CheckboxItem{
			label = a.name,
			hint  = fsx.format_size(size, context.temp_allocator),
		})
		append(&app_paths, strings.clone(a.fullpath, context.temp_allocator))
	}

	if len(rows) == 0 {
		fmt.println("No applications found in /Applications.")
		return 0
	}

	result, _ := tui.checkbox("Select apps to uninstall", rows[:])
	if result != .Submitted {
		fmt.println(util.dim("Cancelled."))
		return 0
	}

	// Build the deletion list for each selected app: bundle + leftovers.
	picked := 0
	plans := make([]AppPlan, len(rows), context.temp_allocator)
	for row, i in rows {
		if !row.selected {
			continue
		}
		picked += 1
		plans[i] = build_app_plan(app_paths[i])
	}
	if picked == 0 {
		fmt.println(util.dim("Nothing selected."))
		return 0
	}

	// Preview / confirm.
	fmt.println()
	fmt.println(util.bold("Will remove:"))
	total: i64 = 0
	for row, i in rows {
		if !row.selected {
			continue
		}
		fmt.printfln("  %s", row.label)
		for path in plans[i].paths {
			size, _ := fsx.dir_size(path)
			total += size
			fmt.printfln("    %s  %s", fsx.format_size(size, context.temp_allocator), fsx.abbreviate(path, context.temp_allocator))
		}
	}
	fmt.println()
	fmt.printfln("Total: %s", fsx.format_size(total, context.temp_allocator))

	if !yes {
		ok := tui.confirm("Proceed?", false)
		if !ok {
			fmt.println(util.dim("Cancelled."))
			return 0
		}
	}

	if dry_run {
		fmt.println(util.dim("--dry-run: no changes made."))
		return 0
	}

	for row, i in rows {
		if !row.selected {
			continue
		}
		for path in plans[i].paths {
			// fsx.safe_delete refuses /Applications/* (in DANGER_PATHS),
			// so we have to fall back to direct os.remove_all for app
			// bundles. Leftover support-files paths under ~/Library
			// pass through safe_delete normally.
			if strings.has_prefix(path, "/Applications/") {
				_ = os.remove_all(path)
			} else {
				_, _ = fsx.safe_delete(path)
			}
		}
	}
	fmt.println(util.green("✓ Uninstall complete"))
	return 0
}

AppPlan :: struct {
	paths: []string,
}

@(private)
build_app_plan :: proc(app_path: string) -> AppPlan {
	// Derive bundle id from app name (best-effort) — used as suffix in
	// support paths like ~/Library/Application Support/<BundleId>.
	base := app_path
	if i := strings.last_index(app_path, "/"); i >= 0 {
		base = app_path[i+1:]
	}
	name := strings.trim_suffix(base, ".app")

	candidates: [dynamic]string
	candidates = make([dynamic]string, 0, 8, context.temp_allocator)
	append(&candidates, strings.clone(app_path, context.temp_allocator))

	home := os.get_env("HOME", context.temp_allocator)
	suffixes := []string{
		"/Library/Application Support/",
		"/Library/Caches/",
		"/Library/Preferences/",
		"/Library/Logs/",
		"/Library/Saved Application State/",
	}
	for s in suffixes {
		guess := strings.concatenate({home, s, name}, context.temp_allocator)
		if _, derr := os.stat(guess, context.temp_allocator); derr == nil {
			append(&candidates, strings.clone(guess, context.temp_allocator))
		}
	}
	return AppPlan{paths = candidates[:]}
}
