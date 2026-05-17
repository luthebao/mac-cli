package cli

import "core:c"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import "mc:util"

// Welcome banner shown when `mac-cli` is invoked with no arguments.
// Single-pane bordered box: title in the top border, Apple mascot
// centered above a short welcome + command list. Auto-sizes to the
// terminal width with a sane cap so it doesn't sprawl on wide displays.

// libSystem on macOS provides ioctl(). We use it solely to query the
// terminal column count for auto-sizing the banner.
foreign import libc "system:System"

@(default_calling_convention = "c")
foreign libc {
	ioctl :: proc(fd: c.int, request: c.ulong, arg: rawptr) -> c.int ---
}

@(private = "file")
Winsize :: struct {
	ws_row, ws_col, ws_xpixel, ws_ypixel: u16,
}

// Darwin/FreeBSD value for TIOCGWINSZ (see core:sys/darwin/xnu_system_call_wrappers).
@(private = "file") TIOCGWINSZ :: 0x40087468

@(private = "file") MIN_BOX_WIDTH :: 44
@(private = "file") MAX_BOX_WIDTH :: 80

// print_welcome renders the banner. VERSION lives in main.odin and is
// passed through to avoid an import cycle.
print_welcome :: proc(version: string) {
	w := box_width()
	inner := w - 4 // 1 border + 1 space on each side

	user := os.get_env("USER", context.temp_allocator)
	if user == "" {
		user = "there"
	}
	cwd_raw, _ := os.get_working_directory(context.temp_allocator)
	cwd := abbreviate_home(cwd_raw, context.temp_allocator)
	arch := "arm64" when ODIN_ARCH == .arm64 else "amd64" when ODIN_ARCH == .amd64 else "unknown"

	// --- Top border with embedded title ---
	title := fmt.aprintf(" mac-cli v%s ", version, allocator = context.temp_allocator)
	lead := 3
	trail := w - 2 - lead - strings.rune_count(title)
	if trail < 3 {
		trail = 3
	}
	fmt.printf(
		"╭%s%s%s╮\n",
		strings.repeat("─", lead, context.temp_allocator),
		title,
		strings.repeat("─", trail, context.temp_allocator),
	)

	// --- Body rows ---
	cwd_meta := fmt.aprintf("%s  ·  %s", util.dim(cwd), util.dim(arch), allocator = context.temp_allocator)

	rows := []string{
		"",
		center("💻", inner, context.temp_allocator),
		"",
		center(fmt.aprintf("Welcome back, %s!", util.bold(user), allocator = context.temp_allocator), inner, context.temp_allocator),
		center(cwd_meta, inner, context.temp_allocator),
		"",
		indent("• mac-cli clean       reclaim disk space", inner),
		indent("• mac-cli shot        screenshot an app or the screen", inner),
		indent("• mac-cli help        show all commands", inner),
		indent("• mac-cli version     print version", inner),
		"",
	}
	for r in rows {
		fmt.printf("│ %s │\n", pad_right(r, inner, context.temp_allocator))
	}

	// --- Bottom border ---
	fmt.printf("╰%s╯\n", strings.repeat("─", w - 2, context.temp_allocator))
	fmt.println()
	fmt.println(util.dim("Run `mac-cli clean` to get started, or `mac-cli help` for the full command list."))
}

// box_width picks a banner width based on terminal columns, clamped to
// a comfortable range. Falls back to MAX_BOX_WIDTH when stdout isn't a TTY.
@(private = "file")
box_width :: proc() -> int {
	cols := term_cols()
	if cols <= 0 {
		return MAX_BOX_WIDTH
	}
	target := cols - 2 // leave a little breathing room on either side
	return clamp(target, MIN_BOX_WIDTH, MAX_BOX_WIDTH)
}

@(private = "file")
term_cols :: proc() -> int {
	ws: Winsize
	// fd 1 = stdout. ioctl returns 0 on success.
	if ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0 {
		return int(ws.ws_col)
	}
	// $COLUMNS is set by interactive shells; honor it as a fallback.
	if env := os.get_env("COLUMNS", context.temp_allocator); env != "" {
		if n, ok := strconv.parse_int(env); ok && n > 0 {
			return n
		}
	}
	return 0
}

// center returns `s` centered within `width` columns, padded on both sides
// with spaces. Width is measured in visible terminal cells (ANSI escapes
// are skipped).
@(private = "file")
center :: proc(s: string, width: int, allocator := context.allocator) -> string {
	vis := visible_width(s)
	if vis >= width {
		return strings.clone(s, allocator)
	}
	left := (width - vis) / 2
	right := width - vis - left
	return strings.concatenate({
		strings.repeat(" ", left, allocator),
		s,
		strings.repeat(" ", right, allocator),
	}, allocator)
}

// indent returns `s` prefixed with a 3-space indent, leaving the rest of
// the row to be filled by pad_right. Used for the command list so it sits
// flush-left consistently regardless of total box width.
@(private = "file")
indent :: proc(s: string, _: int) -> string {
	return strings.concatenate({"   ", s}, context.temp_allocator)
}

@(private = "file")
pad_right :: proc(s: string, width: int, allocator := context.allocator) -> string {
	vis := visible_width(s)
	if vis >= width {
		return strings.clone(s, allocator)
	}
	return strings.concatenate({s, strings.repeat(" ", width - vis, allocator)}, allocator)
}

// visible_width counts the cells `s` would occupy in a terminal, ignoring
// ANSI CSI sequences (ESC '[' params... final-byte 0x40..0x7E). Wide glyphs
// (CJK, emoji) count as 2 cells via rune_cells so centering/padding stays
// correct when the mascot is an emoji like 💻.
@(private = "file")
visible_width :: proc(s: string) -> int {
	State :: enum {Normal, Saw_Esc, In_Csi}
	state := State.Normal
	n := 0
	for r in s {
		switch state {
		case .Normal:
			if r == 0x1b {
				state = .Saw_Esc
			} else {
				n += rune_cells(r)
			}
		case .Saw_Esc:
			if r == '[' {
				state = .In_Csi
			} else {
				state = .Normal
				n += rune_cells(r)
			}
		case .In_Csi:
			if r >= 0x40 && r <= 0x7E {
				state = .Normal
			}
		}
	}
	return n
}

// rune_cells reports the terminal cell width of `r`. Covers the common
// 2-cell ranges (CJK + symbols/pictographs/emoji); everything else is
// treated as 1 cell. Zero-width combiners (e.g. variation selectors)
// aren't handled — the emojis we use don't rely on them.
@(private = "file")
rune_cells :: proc(r: rune) -> int {
	switch {
	case r >= 0x1100  && r <= 0x115F:  return 2 // Hangul Jamo
	case r >= 0x2E80  && r <= 0x303E:  return 2 // CJK radicals/punctuation
	case r >= 0x3041  && r <= 0x33FF:  return 2 // Hiragana/Katakana/CJK symbols
	case r >= 0x3400  && r <= 0x4DBF:  return 2 // CJK Ext A
	case r >= 0x4E00  && r <= 0x9FFF:  return 2 // CJK Unified Ideographs
	case r >= 0xA000  && r <= 0xA4CF:  return 2 // Yi
	case r >= 0xAC00  && r <= 0xD7A3:  return 2 // Hangul Syllables
	case r >= 0xF900  && r <= 0xFAFF:  return 2 // CJK Compatibility
	case r >= 0xFE30  && r <= 0xFE4F:  return 2 // CJK Compatibility Forms
	case r >= 0xFF00  && r <= 0xFF60:  return 2 // Fullwidth Forms
	case r >= 0xFFE0  && r <= 0xFFE6:  return 2 // Fullwidth signs
	case r >= 0x1F300 && r <= 0x1F64F: return 2 // Misc symbols & pictographs
	case r >= 0x1F680 && r <= 0x1F6FF: return 2 // Transport & map
	case r >= 0x1F900 && r <= 0x1F9FF: return 2 // Supplemental symbols
	case r >= 0x20000 && r <= 0x2FFFD: return 2 // CJK Ext B+
	}
	return 1
}

@(private = "file")
abbreviate_home :: proc(p: string, allocator := context.allocator) -> string {
	home := os.get_env("HOME", context.temp_allocator)
	if home != "" && strings.has_prefix(p, home) {
		return strings.concatenate({"~", p[len(home):]}, allocator)
	}
	return strings.clone(p, allocator)
}

