package cli

import "core:fmt"

import tui "mc:clean/tui"
import "mc:util"

// Interactive command picker. Used in two shapes:
//
//   1. `run_menu(version)` — entered when `mac-cli` is run with no args.
//      Walks the full tree (top → subtree → leaf) and returns a MenuResult
//      that main.odin dispatches.
//
//   2. `pick_at(path...)` — entered by each command's dispatch when it gets
//      no args (e.g. `mac-cli clean` or `mac-cli clean config`). Starts at
//      the named subtree and returns the leaf args directly.
//
// We intentionally don't import clean/clop/shot/update here — those packages
// import `mc:cli` for the flag parser, so a back-import would cycle. The
// menu's job is to *collect* args; routing them lives in each dispatch.

@(private="file") MAX_VISIBLE :: 12

MenuAction :: enum {
	None,    // user cancelled / no action
	Help,    // selected "help" — main prints TOP_USAGE
	Version, // selected "version" — main prints the version string
	Quit,    // selected "quit" — main exits cleanly
	Clean,   // dispatch clean with .args
	Clop,    // dispatch clop with .args
	Shot,    // dispatch shot with .args
	Update,  // dispatch update with .args
}

MenuResult :: struct {
	action: MenuAction,
	args:   []string, // forwarded verbatim to the chosen dispatch proc
}

// MenuItem is one row in a menu. A row is either a *leaf* (children empty —
// picking returns `args` to the caller) or a *branch* (children non-empty —
// picking drills into a sub-menu, args ignored). `is_back` marks the
// synthetic "← back" row that returns control to the parent menu.
MenuItem :: struct {
	label:    string,
	detail:   string,
	args:     []string,
	children: []MenuItem,
	is_back:  bool,
}

// PickStatus distinguishes three end-states of a single menu interaction.
// We need three because Esc and "← back" do different things: Esc bubbles
// all the way up to exit the program, while "← back" only unwinds one
// level so the parent menu can redisplay. A simple bool wouldn't suffice.
@(private)
PickStatus :: enum {
	Selected, // user picked a leaf — args populated
	Back,     // user picked ← back — unwind one level only
	Cancel,   // user pressed Esc / Ctrl-C — propagate up, exit
}

// ── arg-slice storage ───────────────────────────────────────────────────────
//
// MenuItem.args is a []string. Slice headers reference backing storage that
// must outlive the menu call, so the arrays are declared at package scope.
// Returning a slice of a stack-allocated compound literal from a procedure
// would dangle.

@(private="file") ARGS_CLEAN_INTERACTIVE  := [?]string{"interactive"}
@(private="file") ARGS_CLEAN_DEEP         := [?]string{"deep"}
@(private="file") ARGS_CLEAN_UNINSTALL    := [?]string{"uninstall"}
@(private="file") ARGS_CLEAN_INSIGHTS     := [?]string{"insights"}
@(private="file") ARGS_CLEAN_MONITOR      := [?]string{"monitor"}
@(private="file") ARGS_CLEAN_CATEGORIES   := [?]string{"categories"}
@(private="file") ARGS_CLEAN_HELP         := [?]string{"help"}

@(private="file") ARGS_CLEAN_MAINT_DNS    := [?]string{"maintenance", "--dns"}
@(private="file") ARGS_CLEAN_MAINT_PURGE  := [?]string{"maintenance", "--purgeable"}
@(private="file") ARGS_CLEAN_MAINT_TM     := [?]string{"maintenance", "--timemachine"}
@(private="file") ARGS_CLEAN_MAINT_HELP   := [?]string{"maintenance", "--help"}

@(private="file") ARGS_CLEAN_CONFIG_INIT  := [?]string{"config", "--init"}
@(private="file") ARGS_CLEAN_CONFIG_SHOW  := [?]string{"config", "--show"}
@(private="file") ARGS_CLEAN_CONFIG_HELP  := [?]string{"config", "--help"}

@(private="file") ARGS_CLEAN_BACKUP_LIST  := [?]string{"backup", "--list"}
@(private="file") ARGS_CLEAN_BACKUP_CLEAN := [?]string{"backup", "--clean"}
@(private="file") ARGS_CLEAN_BACKUP_HELP  := [?]string{"backup", "--help"}

@(private="file") ARGS_SHOT_INTERACTIVE := [?]string{"interactive"}
@(private="file") ARGS_SHOT_SCREEN      := [?]string{"-s"}
@(private="file") ARGS_SHOT_LIST        := [?]string{"-l"}
@(private="file") ARGS_SHOT_HELP        := [?]string{"-h"}

@(private="file") ARGS_UPDATE_INSTALL := [?]string{"install"}
@(private="file") ARGS_UPDATE_CHECK   := [?]string{"--check"}
@(private="file") ARGS_UPDATE_FORCE   := [?]string{"--force"}
@(private="file") ARGS_UPDATE_HELP    := [?]string{"--help"}

// Backing storage for the "no args, enter interactive wizard" case used by
// clop. Returning `args = nil` from a struct compound literal trips Odin's
// "compound literal of a slice uses stack memory" check; a package-scope
// (zero-length) backing array sidesteps that.
@(private="file") ARGS_CLOP_EMPTY := [?]string{}

// Sub-trees for clean/config, clean/maintenance, clean/backup. Defined first
// because they're referenced from `clean_tree` below.

@(private="file")
clean_maint_tree := []MenuItem{
	{label = "dns",         detail = "flush DNS cache (sudo)",         args = ARGS_CLEAN_MAINT_DNS[:]},
	{label = "purgeable",   detail = "thin Time Machine local snaps",  args = ARGS_CLEAN_MAINT_PURGE[:]},
	{label = "timemachine", detail = "list local TM snapshots",        args = ARGS_CLEAN_MAINT_TM[:]},
	{label = "help",        detail = "show maintenance help",          args = ARGS_CLEAN_MAINT_HELP[:]},
	{label = "← back",      detail = "return to the clean menu",       is_back = true},
}

@(private="file")
clean_config_tree := []MenuItem{
	{label = "init",   detail = "create default config",       args = ARGS_CLEAN_CONFIG_INIT[:]},
	{label = "show",   detail = "print current effective config", args = ARGS_CLEAN_CONFIG_SHOW[:]},
	{label = "help",   detail = "show config help",            args = ARGS_CLEAN_CONFIG_HELP[:]},
	{label = "← back", detail = "return to the clean menu",    is_back = true},
}

@(private="file")
clean_backup_tree := []MenuItem{
	{label = "list",   detail = "list backup sessions",        args = ARGS_CLEAN_BACKUP_LIST[:]},
	{label = "clean",  detail = "remove sessions > 7 days",    args = ARGS_CLEAN_BACKUP_CLEAN[:]},
	{label = "help",   detail = "show backup help",            args = ARGS_CLEAN_BACKUP_HELP[:]},
	{label = "← back", detail = "return to the clean menu",    is_back = true},
}

@(private="file")
clean_tree := []MenuItem{
	{label = "interactive", detail = "scan → select → clean (default)", args = ARGS_CLEAN_INTERACTIVE[:]},
	{label = "deep",        detail = "deep clean — scan everything",    args = ARGS_CLEAN_DEEP[:]},
	{label = "uninstall",   detail = "remove apps and their files",     args = ARGS_CLEAN_UNINSTALL[:]},
	{label = "insights",    detail = "where did my disk space go?",     args = ARGS_CLEAN_INSIGHTS[:]},
	{label = "monitor",     detail = "live CPU/mem/disk/net dashboard", args = ARGS_CLEAN_MONITOR[:]},
	{label = "maintenance", detail = "DNS / purgeable / snapshots",     children = clean_maint_tree},
	{label = "categories",  detail = "list cleanable categories",       args = ARGS_CLEAN_CATEGORIES[:]},
	{label = "config",      detail = "manage clean config",             children = clean_config_tree},
	{label = "backup",      detail = "manage pre-delete backups",       children = clean_backup_tree},
	{label = "help",        detail = "show clean help",                 args = ARGS_CLEAN_HELP[:]},
	{label = "← back",      detail = "return to the main menu",         is_back = true},
}

@(private="file")
shot_tree := []MenuItem{
	{label = "interactive", detail = "type-to-filter app picker (default)", args = ARGS_SHOT_INTERACTIVE[:]},
	{label = "full screen", detail = "capture the whole screen (-s)",       args = ARGS_SHOT_SCREEN[:]},
	{label = "list apps",   detail = "list running GUI apps (-l)",          args = ARGS_SHOT_LIST[:]},
	{label = "help",        detail = "show shot help",                      args = ARGS_SHOT_HELP[:]},
	{label = "← back",      detail = "return to the main menu",             is_back = true},
}

@(private="file")
update_tree := []MenuItem{
	{label = "install", detail = "install if newer release exists (default)", args = ARGS_UPDATE_INSTALL[:]},
	{label = "check",   detail = "only report — don't install (--check)",     args = ARGS_UPDATE_CHECK[:]},
	{label = "force",   detail = "re-run installer (--force)",                args = ARGS_UPDATE_FORCE[:]},
	{label = "help",    detail = "show update help",                          args = ARGS_UPDATE_HELP[:]},
	{label = "← back",  detail = "return to the main menu",                   is_back = true},
}

// tree_for returns the sub-tree rooted at the named path. `path` is the
// command path *below* the top level — e.g. `"clean"` or `"clean", "config"`.
// Returns nil if the path doesn't resolve.
@(private="file")
tree_for :: proc(path: ..string) -> []MenuItem {
	if len(path) == 0 { return nil }

	current: []MenuItem
	switch path[0] {
	case "clean":  current = clean_tree
	case "shot":   current = shot_tree
	case "update": current = update_tree
	case:          return nil
	}

	for p in path[1:] {
		next: []MenuItem = nil
		for it in current {
			if it.label == p && len(it.children) > 0 {
				next = it.children
				break
			}
		}
		if next == nil { return nil }
		current = next
	}
	return current
}

@(private="file")
title_for :: proc(path: ..string) -> string {
	switch len(path) {
	case 1:
		return fmt.tprintf("mac-cli %s — pick a subcommand", path[0])
	case 2:
		return fmt.tprintf("mac-cli %s %s — pick an action", path[0], path[1])
	case:
		return "mac-cli — pick a command"
	}
}

// ── public entry points ────────────────────────────────────────────────────

// run_menu drives the *top-level* interactive picker, returning a MenuResult
// that main.odin dispatches. Falls back to the textual welcome banner when
// stdin is not a TTY — the menu would have no keys to read.
run_menu :: proc(version: string) -> MenuResult {
	if !tty_available() {
		print_welcome(version)
		return {action = .None}
	}

	top := []MenuItem{
		{label = "clean",   detail = "reclaim disk space"},
		{label = "clop",    detail = "optimise images and videos"},
		{label = "shot",    detail = "screenshot an app or the screen"},
		{label = "update",  detail = "install the latest release"},
		{label = "help",    detail = "show the full command list"},
		{label = "version", detail = "print the installed version"},
		{label = "quit",    detail = "exit without doing anything"},
	}

	for {
		title := fmt.tprintf("mac-cli v%s — pick a command", version)
		idx, ok := pick(title, top)
		if !ok {
			return {action = .Quit}
		}
		chosen := top[idx]

		switch chosen.label {
		case "clean":
			args, st := walk(clean_tree, "clean")
			if st == .Selected { return {action = .Clean, args = args} }
			if st == .Cancel   { return {action = .Quit} }
			// Back: redisplay top menu
			continue
		case "shot":
			args, st := walk(shot_tree, "shot")
			if st == .Selected { return {action = .Shot, args = args} }
			if st == .Cancel   { return {action = .Quit} }
			continue
		case "update":
			args, st := walk(update_tree, "update")
			if st == .Selected { return {action = .Update, args = args} }
			if st == .Cancel   { return {action = .Quit} }
			continue
		case "clop":
			// clop has its own multi-step wizard (run_interactive). Hand off
			// with empty args — clop.dispatch routes empty args to the wizard.
			return {action = .Clop, args = ARGS_CLOP_EMPTY[:]}
		case "help":
			return {action = .Help}
		case "version":
			return {action = .Version}
		case "quit":
			return {action = .Quit}
		}
	}
}

// pick_at is the entry point used by each command's dispatch when it gets
// no args. `path` names the subtree to start at — e.g. `"clean"` for the
// clean menu, or `"clean", "config"` for the config submenu. Returns the
// leaf args (relative to the *full* command line, so a caller at
// `mac-cli clean config` gets `["--show"]`, not `["config", "--show"]` —
// see the per-level args definitions above).
//
// Returns (nil, false) when the user cancels (Esc) or backs out (← back).
// The caller treats both as "exit this level" — dispatch returns 0.
pick_at :: proc(path: ..string) -> ([]string, bool) {
	if !tty_available() { return nil, false }
	items := tree_for(..path)
	if items == nil { return nil, false }

	args, st := walk(items, ..path)
	if st != .Selected { return nil, false }

	// Strip the path prefix from absolute args so the caller sees args
	// relative to its level. e.g. pick_at("clean", "config") with leaf
	// args ["config", "--show"] returns ["--show"]. The first path element
	// is the top-level command and is *not* in the args — it was already
	// consumed by main.odin to dispatch to clean.dispatch.
	strip := len(path) - 1
	if strip <= 0 || strip > len(args) { return args, true }
	return args[strip:], true
}

// ── internals ──────────────────────────────────────────────────────────────

// walk drills down into a menu tree. Returns once the user has either
// selected a leaf, backed out, or cancelled. `path` is used purely for
// building the title — the tree itself is `items`.
@(private)
walk :: proc(items: []MenuItem, path: ..string) -> ([]string, PickStatus) {
	for {
		title := title_for(..path)
		idx, ok := pick(title, items)
		if !ok {
			return nil, .Cancel
		}
		chosen := items[idx]
		if chosen.is_back {
			return nil, .Back
		}
		if len(chosen.children) > 0 {
			sub_path := make([]string, len(path) + 1, context.temp_allocator)
			copy(sub_path, path)
			sub_path[len(path)] = chosen.label

			args, st := walk(chosen.children, ..sub_path)
			switch st {
			case .Selected: return args, .Selected
			case .Cancel:   return nil,  .Cancel
			case .Back:     continue // redisplay current menu
			}
		}
		return chosen.args, .Selected
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
pick :: proc(title: string, items: []MenuItem) -> (selected: int, ok: bool) {
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
render :: proc(title: string, items: []MenuItem, cursor: int) -> int {
	fmt.println(util.bold(title, context.temp_allocator))
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
	// so we need the cursor on the last content row — not on the blank row
	// below it — for the next iteration's redraw to overwrite cleanly.
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
