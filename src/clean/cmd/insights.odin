package clean_cmd

import "core:fmt"
import "core:strconv"
import "core:strings"

import "mc:cli"
import "mc:clean/insights"
import "mc:fsx"
import "mc:util"

@(private="file") BAR_WIDTH :: 18
@(private="file") MAX_ROWS  :: 15

// run_insights renders a one-shot "where did my disk go?" report for a path
// (default: $HOME): the largest direct children with proportional bars, the
// largest individual files, and "hidden space" callouts.
run_insights :: proc(args: []string) -> int {
	spec := []cli.Flag{
		{name = "help", short = "h", takes_value = false},
		{name = "top",  short = "n", takes_value = true},
	}
	p := cli.parse(args, spec)

	if cli.bool_flag(p, "help") {
		fmt.println(
`mac-cli clean insights — see where your disk space went

USAGE
  mac-cli clean insights [path] [--top N]

ARGUMENTS
  path       Directory to analyze (default: your home folder)

OPTIONS
  --top, -n  How many "largest files" to list (default: 10)

Shows the largest folders/files under the path with size bars, plus hidden
space (caches, iOS backups, old downloads). Large folders can take a moment.
`)
		return 0
	}

	root := "~"
	if len(p.positional) > 0 {
		root = p.positional[0]
	}

	top := 10
	if v := cli.string_flag(p, "top"); v != "" {
		if n, ok := strconv.parse_int(v); ok && n > 0 {
			top = n
		}
	}

	fmt.printfln("%s %s", util.bold("Analyzing"), fsx.abbreviate(fsx.expand(root, context.temp_allocator), context.temp_allocator))
	fmt.println(util.dim("Measuring directory sizes — this can take a moment on large folders…"))
	fmt.println()

	rep := insights.analyze(root, top, context.temp_allocator)

	if rep.total_size == 0 && len(rep.entries) == 0 {
		fmt.println(util.dim("Nothing found — is the path readable?"))
		return 0
	}

	// ── breakdown ──────────────────────────────────────────────────────────
	fmt.printfln("%s  %s  |  Total: %s",
		util.bold("Disk Insights"),
		fsx.abbreviate(rep.root, context.temp_allocator),
		util.bold(fsx.format_size(rep.total_size, context.temp_allocator)))
	fmt.println(strings.repeat("─", 64, context.temp_allocator))

	max_size: i64 = 1
	if len(rep.entries) > 0 {
		max_size = rep.entries[0].size
	}
	shown := min(MAX_ROWS, len(rep.entries))
	for i in 0 ..< shown {
		e := rep.entries[i]
		pct: f64 = 0
		if rep.total_size > 0 {
			pct = f64(e.size) / f64(rep.total_size) * 100
		}
		icon := e.is_dir ? "📁" : "📄"
		// %6s wrapper, not %6.1f: Odin's float width specifier zero-pads.
		fmt.printfln("  %s  %s  %s %-28s %s",
			fmt.tprintf("%6s", fmt.tprintf("%.1f%%", pct)),
			size_bar(f64(e.size) / f64(max_size), context.temp_allocator),
			icon,
			truncate(e.name, 28),
			fsx.format_size(e.size, context.temp_allocator))
	}

	// ── largest files ──────────────────────────────────────────────────────
	if len(rep.largest) > 0 {
		fmt.println()
		fmt.println(util.bold("Largest files"))
		for f in rep.largest {
			fmt.printfln("  %10s  %s",
				fsx.format_size(f.size, context.temp_allocator),
				util.dim(fsx.abbreviate(f.path, context.temp_allocator), context.temp_allocator))
		}
	}

	// ── hidden space ───────────────────────────────────────────────────────
	if len(rep.insights) > 0 {
		fmt.println()
		fmt.println(util.bold("Hidden space"))
		hidden_total: i64 = 0
		for ins in rep.insights {
			hidden_total += ins.size
			tag := ins.safe ? util.green(" safe to clean", context.temp_allocator) : util.yellow(" holds real data", context.temp_allocator)
			fmt.printfln("  👀 %-22s %10s %s",
				truncate(ins.name, 22),
				fsx.format_size(ins.size, context.temp_allocator),
				tag)
		}
		fmt.println(strings.repeat("─", 64, context.temp_allocator))
		fmt.printfln("  Hidden space total: %s   %s",
			util.bold(fsx.format_size(hidden_total, context.temp_allocator)),
			util.dim("→ run `mac-cli clean` to reclaim the safe ones", context.temp_allocator))
	}

	return 0
}

// size_bar renders a proportional bar: `frac` (0..1) of BAR_WIDTH cells filled
// with █, the rest ░. The filled run is colored so the eye lands on the big
// consumers; the remainder is dimmed.
@(private="file")
size_bar :: proc(frac: f64, allocator := context.allocator) -> string {
	f := frac
	if f < 0 { f = 0 }
	if f > 1 { f = 1 }
	filled := int(f * f64(BAR_WIDTH) + 0.5)
	if filled > BAR_WIDTH { filled = BAR_WIDTH }

	full := strings.repeat("█", filled, context.temp_allocator)
	rest := strings.repeat("░", BAR_WIDTH - filled, context.temp_allocator)
	return strings.concatenate({util.cyan(full, context.temp_allocator), util.dim(rest, context.temp_allocator)}, allocator)
}

// truncate clips a string to n runes, appending "…" when cut. Keeps columns
// aligned when a folder name is longer than the field width.
@(private="file")
truncate :: proc(s: string, n: int) -> string {
	if len(s) <= n {
		return s
	}
	if n <= 1 {
		return s[:n]
	}
	return fmt.tprintf("%s…", s[:n - 1])
}
