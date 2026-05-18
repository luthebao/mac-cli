package cli

import "core:fmt"

import tui "mc:clean/tui"
import "mc:util"

// Interactive menu shown when `mac-cli` is invoked with no arguments.
// Two levels: a top menu listing commands, and submenus for clean/shot/update.
// Picking a leaf returns a MenuResult; main dispatches based on it. We
// intentionally don't import clean/shot/update here — that would create a
// cycle since those packages import `mc:cli` for the flag parser.

@(private="file") MAX_VISIBLE :: 12

MenuAction :: enum {
	None,    // user cancelled / no action
	Help,    // selected "help" — main prints TOP_USAGE
	Version, // selected "version" — main prints the version string
	Quit,    // selected "quit" — main exits cleanly
	Clean,   // dispatch clean with .args
	Shot,    // dispatch shot with .args
	Update,  // dispatch update with .args
}

MenuResult :: struct {
	action: MenuAction,
	args:   []string, // forwarded verbatim to the chosen dispatch proc
}

// Submenu arg slices. Declared at package scope so the []string headers in
// `Item.args` reference storage that outlives `run_menu`. Returning a slice
// of a stack-allocated compound literal would dangle.
@(private="file") ARGS_CLEAN_UNINSTALL   := [?]string{"uninstall"}
@(private="file") ARGS_CLEAN_MAINTENANCE := [?]string{"maintenance"}
@(private="file") ARGS_CLEAN_CATEGORIES  := [?]string{"categories"}
@(private="file") ARGS_CLEAN_CONFIG      := [?]string{"config"}
@(private="file") ARGS_CLEAN_BACKUP      := [?]string{"backup"}
@(private="file") ARGS_SHOT_SCREEN       := [?]string{"-s"}
@(private="file") ARGS_SHOT_LIST         := [?]string{"-l"}
@(private="file") ARGS_UPDATE_CHECK      := [?]string{"--check"}
@(private="file") ARGS_UPDATE_FORCE      := [?]string{"--force"}

@(private="file")
Item :: struct {
	label:   string,
	detail:  string,
	action:  MenuAction,
	args:    []string,
	is_back: bool, // when true, picking this item returns to the parent menu
}

// run_menu drives the interactive picker. Falls back to printing the welcome
// banner (the textual command list) when stdin is not a TTY — the menu would
// have nothing to read keys from.
run_menu :: proc(version: string) -> MenuResult {
	if !tty_available() {
		print_welcome(version)
		return {action = .None}
	}

	top := []Item{
		{label = "clean",   detail = "reclaim disk space",                action = .Clean},
		{label = "shot",    detail = "screenshot an app or the screen",   action = .Shot},
		{label = "update",  detail = "install the latest release",        action = .Update},
		{label = "help",    detail = "show the full command list",        action = .Help},
		{label = "version", detail = "print the installed version",       action = .Version},
		{label = "quit",    detail = "exit without doing anything",       action = .Quit},
	}

	clean_sub := []Item{
		{label = "interactive", detail = "scan → select → clean (default)", action = .Clean},
		{label = "uninstall",   detail = "remove apps and their files",      action = .Clean, args = ARGS_CLEAN_UNINSTALL[:]},
		{label = "maintenance", detail = "DNS flush, purgeable, snapshots",  action = .Clean, args = ARGS_CLEAN_MAINTENANCE[:]},
		{label = "categories",  detail = "list cleanable categories",        action = .Clean, args = ARGS_CLEAN_CATEGORIES[:]},
		{label = "config",      detail = "manage clean config",              action = .Clean, args = ARGS_CLEAN_CONFIG[:]},
		{label = "backup",      detail = "manage pre-delete backups",        action = .Clean, args = ARGS_CLEAN_BACKUP[:]},
		{label = "← back",      detail = "return to the main menu",          is_back = true},
	}

	shot_sub := []Item{
		{label = "interactive", detail = "type-to-filter app picker (default)", action = .Shot},
		{label = "full screen", detail = "capture the whole screen (-s)",       action = .Shot, args = ARGS_SHOT_SCREEN[:]},
		{label = "list apps",   detail = "list running GUI apps (-l)",          action = .Shot, args = ARGS_SHOT_LIST[:]},
		{label = "← back",      detail = "return to the main menu",             is_back = true},
	}

	update_sub := []Item{
		{label = "install", detail = "install if a newer release exists (default)", action = .Update},
		{label = "check",   detail = "only report — don't install (--check)",       action = .Update, args = ARGS_UPDATE_CHECK[:]},
		{label = "force",   detail = "re-run the installer (--force)",              action = .Update, args = ARGS_UPDATE_FORCE[:]},
		{label = "← back",  detail = "return to the main menu",                     is_back = true},
	}

	for {
		title := fmt.tprintf("mac-cli v%s — pick a command", version)
		idx, ok := pick(title, top)
		if !ok {
			return {action = .Quit}
		}
		chosen := top[idx]

		sub: []Item
		sub_title: string
		switch chosen.action {
		case .Clean:
			sub, sub_title = clean_sub, "mac-cli clean — pick a subcommand"
		case .Shot:
			sub, sub_title = shot_sub, "mac-cli shot — pick a mode"
		case .Update:
			sub, sub_title = update_sub, "mac-cli update — pick an action"
		case .Help, .Version, .Quit:
			return {action = chosen.action}
		case .None:
			return {action = .Quit}
		}

		sidx, sok := pick(sub_title, sub)
		if !sok {
			return {action = .Quit}
		}
		if sub[sidx].is_back {
			continue
		}
		return {action = sub[sidx].action, args = sub[sidx].args}
	}
}

// tty_available checks whether we can enter raw mode at all. We probe by
// entering and immediately restoring so the menu state stays clean.
@(private="file")
tty_available :: proc() -> bool {
	if !tui.enter_raw() {
		return false
	}
	tui.restore()
	return true
}

// pick renders a single-pane list picker and blocks until the user selects
// an item (returns its index + ok=true) or cancels with Esc/Ctrl-C/Ctrl-D
// (returns ok=false). On selection we clear the rendered lines so subsequent
// output (a submenu, or a dispatched command) starts from a clean slate.
@(private="file")
pick :: proc(title: string, items: []Item) -> (selected: int, ok: bool) {
	if len(items) == 0 {
		return 0, false
	}
	if !tui.enter_raw() {
		return 0, false
	}
	defer tui.restore()
	tui.hide_cursor()
	defer tui.show_cursor()

	cursor := 0
	last_lines := 0

	for {
		tui.clear_lines(last_lines)
		last_lines = render(title, items, cursor)

		k := tui.read_key()
		#partial switch k {
		case .Up:
			cursor = (cursor - 1 + len(items)) % len(items)
		case .Down:
			cursor = (cursor + 1) % len(items)
		case .Enter:
			tui.clear_lines(last_lines)
			return cursor, true
		case .Esc, .Ctrl_C, .Ctrl_D:
			tui.clear_lines(last_lines)
			return 0, false
		}
	}
}

@(private="file")
render :: proc(title: string, items: []Item, cursor: int) -> int {
	fmt.println(util.bold(title))
	fmt.println()
	lines := 2

	start, end := window_around(cursor, len(items), MAX_VISIBLE)
	for i in start..<end {
		it := items[i]
		marker := "  "
		if i == cursor {
			marker = util.cyan("→ ", context.temp_allocator)
		}
		row: string
		if it.detail == "" {
			row = fmt.tprintf("%s%s", marker, it.label)
		} else {
			row = fmt.tprintf("%s%-13s  %s", marker, it.label, util.dim(it.detail, context.temp_allocator))
		}
		fmt.println(row)
		lines += 1
	}
	if len(items) > MAX_VISIBLE {
		more := fmt.tprintf("  showing %d–%d of %d", start+1, end, len(items))
		fmt.println(util.dim(more, context.temp_allocator))
		lines += 1
	}
	// Final line uses `print` (no trailing newline) so the cursor stays on
	// the hint row. clear_lines(N) clears N rows from the cursor going up,
	// so we need cursor on the last content row — not on the blank row
	// below it — for the next iteration's redraw to overwrite cleanly.
	// Without this, every redraw left the top row uncleared, and the menu
	// "drifted" down by one row per keypress / per leaked input byte.
	fmt.print(util.dim("↑↓ navigate · ⏎ select · Esc cancel", context.temp_allocator))
	return lines + 1
}

// window_around mirrors the helper in shot/tui.odin: pick a [start, end)
// slice of length ≤ max_visible that keeps the cursor centered when possible.
@(private="file")
window_around :: proc(cursor, n, max_visible: int) -> (start, end: int) {
	if n <= max_visible {
		return 0, n
	}
	half := max_visible / 2
	start = cursor - half
	if start < 0 {
		start = 0
	}
	end = start + max_visible
	if end > n {
		end = n
		start = n - max_visible
	}
	return
}
