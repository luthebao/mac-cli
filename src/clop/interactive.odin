package clop

import "core:fmt"
import "core:os"
import "core:strings"

import tui "mc:clean/tui"
import "mc:util"

// run_interactive is invoked when the user runs `mac-cli clop` with no
// arguments. It walks them through:
//   1. pick an operation        (TUI list)
//   2. enter a path             (cooked-mode line read)
//   3. extras per operation     (factor for -d, format pick for -c)
// then hands off to the existing run_* handlers.
run_interactive :: proc() -> int {
	if !tui.enter_raw() {
		// No TTY available — fall back to printing help so a CI/pipe
		// invocation still gives the user something useful.
		print_help()
		return 0
	}
	tui.restore() // we'll re-enter for each pick step explicitly

	// Belt-and-braces: if any inner step leaves the terminal in raw mode
	// (panic, early return, deferred restore hasn't run yet), this guard
	// puts the terminal back before we return to the caller. restore() is
	// idempotent — safe to call on an already-restored terminal.
	defer tui.restore()

	opts: Options

	op, want_help, op_ok := pick_op()
	if !op_ok { return 0 }
	if want_help {
		print_help()
		return 0
	}
	opts.op = op

	// Echo the choice so the next prompt has context. After pick_index
	// clears its rendered lines, the screen would otherwise jump straight
	// from "(picker disappeared)" to "Downscale factor:" with no visible
	// link between them.
	echo_choice("operation", op_label(op))

	switch op {
	case .Optimise, .StripExif:
		// no extras
	case .Downscale:
		f, f_ok := prompt_factor()
		if !f_ok { return 0 }
		opts.factor = f
	case .Convert:
		fmt_str, fmt_ok := pick_format()
		if !fmt_ok { return 0 }
		opts.to_format = fmt_str
		echo_choice("target format", fmt_str)
	case .None:
		return 0
	}

	path, path_ok := prompt_path()
	if !path_ok { return 0 }
	opts.target_path = path

	// Modifiers (-a, -r, -k) are intentionally NOT prompted. Adding three
	// extra y/N prompts to every interactive run turns a 4-step flow into
	// a 7-step one. Users who want them re-invoke with explicit flags —
	// the help text documents that.
	fmt.println() // visual separator before run output

	switch opts.op {
	case .Optimise:  return run_optimise(opts)
	case .Downscale: return run_downscale(opts)
	case .Convert:   return run_convert(opts)
	case .StripExif: return run_stripexif(opts)
	case .None:      return 0
	}
	return 0
}

// ── op picker ────────────────────────────────────────────────────────────

@(private)
OpItem :: struct {
	op:      Op,
	label:   string,
	detail:  string,
	is_help: bool, // when true, picking this row prints clop's help text
	is_back: bool, // when true, picking this row exits the wizard
}

// "help" and "← back" are included so the wizard mirrors the other commands'
// menus — every TUI lists `help` and a back entry. Picking help sets the
// `want_help` return; picking back behaves like Esc and cancels the wizard
// (there is no parent menu to return to because clop is dispatched as a
// leaf from the top-level menu).
@(private)
op_items := []OpItem{
	{.Optimise,  "optimise",  "compress in place (same format)", false, false},
	{.Downscale, "downscale", "resize by factor",                false, false},
	{.Convert,   "convert",   "to webp / heic / avif",           false, false},
	{.StripExif, "stripexif", "drop metadata",                   false, false},
	{.None,      "help",      "show clop help",                  true,  false},
	{.None,      "← back",    "exit the wizard",                 false, true},
}

@(private)
pick_op :: proc() -> (op: Op, want_help: bool, ok: bool) {
	idx, k := pick_index("mac-cli clop — pick an operation",
		op_labels(),
		op_details())
	if !k { return .None, false, false }
	it := op_items[idx]
	if it.is_back { return .None, false, false }
	if it.is_help { return .None, true, true }
	return it.op, false, true
}

@(private)
op_label :: proc(op: Op) -> string {
	for it in op_items {
		if it.op == op { return it.label }
	}
	return ""
}

@(private)
echo_choice :: proc(field, value: string) {
	label := fmt.tprintf("%s:", field)
	fmt.printfln("  %s %s %s",
		util.dim(label, context.temp_allocator),
		util.cyan("→", context.temp_allocator),
		value)
}

@(private)
op_labels :: proc() -> []string {
	out := make([]string, len(op_items), context.temp_allocator)
	for it, i in op_items { out[i] = it.label }
	return out
}

@(private)
op_details :: proc() -> []string {
	out := make([]string, len(op_items), context.temp_allocator)
	for it, i in op_items { out[i] = it.detail }
	return out
}

// ── format picker (for -c) ───────────────────────────────────────────────

@(private)
format_labels := [?]string{"webp", "heic", "avif", "← back"}
@(private)
format_details := [?]string{
	"google's web image format (cwebp)",
	"apple's modern image format (heif-enc)",
	"av1-based image format (heif-enc --avif)",
	"exit the wizard",
}

@(private)
pick_format :: proc() -> (string, bool) {
	idx, ok := pick_index("mac-cli clop -c — pick a target format",
		format_labels[:],
		format_details[:])
	if !ok { return "", false }
	// Last row is the synthetic ← back entry. Treat it like Esc.
	if idx == len(format_labels) - 1 { return "", false }
	return strings.clone(format_labels[idx]), true
}

// ── shared list picker ───────────────────────────────────────────────────

// pick_index is a minimal copy of cli.pick — we don't share the one in
// cli/menu.odin because it's `@(private="file")` and operates on a private
// Item type. Reproducing the loop locally is cheaper than refactoring.
@(private)
pick_index :: proc(title: string, labels, details: []string) -> (int, bool) {
	if len(labels) == 0 { return 0, false }
	if !tui.enter_raw() { return 0, false }
	defer tui.restore()
	tui.hide_cursor()
	defer tui.show_cursor()

	cursor := 0
	last_lines := 0

	for {
		tui.clear_lines(last_lines)
		last_lines = render_picker(title, labels, details, cursor)
		k := tui.read_key()
		#partial switch k {
		case .Up:    cursor = (cursor - 1 + len(labels)) % len(labels)
		case .Down:  cursor = (cursor + 1) % len(labels)
		case .Enter:
			tui.clear_lines(last_lines)
			return cursor, true
		case .Esc, .Ctrl_C, .Ctrl_D:
			tui.clear_lines(last_lines)
			return 0, false
		}
	}
}

@(private)
render_picker :: proc(title: string, labels, details: []string, cursor: int) -> int {
	fmt.println(util.bold(title))
	fmt.println()
	lines := 2
	for label, i in labels {
		marker := "  "
		if i == cursor {
			marker = util.cyan("→ ", context.temp_allocator)
		}
		detail := details[i] if i < len(details) else ""
		row := fmt.tprintf("%s%-12s  %s",
			marker, label,
			util.dim(detail, context.temp_allocator))
		fmt.println(row)
		lines += 1
	}
	fmt.print(util.dim("↑↓ navigate · ⏎ select · Esc cancel", context.temp_allocator))
	return lines + 1
}

// ── text input (cooked mode) ─────────────────────────────────────────────

// prompt_path reads a path string. We exit raw mode (already restored by
// pick_index) so the user gets normal line editing — backspace, paste,
// arrow keys all work. Drag-and-drop from Finder onto Terminal pastes the
// quoted absolute path, which we strip below.
@(private)
prompt_path :: proc() -> (string, bool) {
	fmt.print(util.bold("Path (file or directory): "))
	line, ok := read_line()
	if !ok { return "", false }
	line = strings.trim_space(line)
	if line == "" { return "", false }

	// Finder-drag pastes a shell-quoted path like `'/Users/me/foo.png'`
	// or a backslash-escaped one. Strip the obvious wrappers.
	line = strings.trim(line, "'\"")
	// Expand a leading `~` to $HOME; we don't do full word expansion.
	if strings.has_prefix(line, "~/") {
		home := os.get_env("HOME", context.temp_allocator)
		if home != "" {
			line = strings.concatenate({home, line[1:]}, context.temp_allocator)
		}
	}
	return strings.clone(line), true
}

@(private)
prompt_factor :: proc() -> (f64, bool) {
	for {
		fmt.print(util.bold("Downscale factor (e.g. 0.5 or 50%): "))
		line, ok := read_line()
		if !ok { return 0, false }
		f, f_ok := parse_factor(strings.trim_space(line))
		if f_ok { return f, true }
		fmt.println(util.yellow("  invalid factor — try again, or Ctrl-D to cancel", context.temp_allocator))
	}
}

// read_line reads a line from stdin in cooked mode. Reads byte-at-a-time
// because the kernel buffers a full line for us in canonical mode — the
// loop terminates at '\n' or on EOF (Ctrl-D on an empty line). Returning
// ok=false signals the user cancelled with Ctrl-D.
@(private)
read_line :: proc() -> (string, bool) {
	buf := make([dynamic]u8, 0, 256, context.temp_allocator)
	one: [1]u8
	for {
		n, err := os.read(os.stdin, one[:])
		if err != nil || n <= 0 {
			if len(buf) == 0 { return "", false } // EOF on empty
			break
		}
		c := one[0]
		if c == '\n' { break }
		if c == '\r' { continue }
		append(&buf, c)
	}
	if len(buf) == 0 { return "", true } // empty line is OK; caller decides
	return strings.clone(string(buf[:]), context.temp_allocator), true
}
