package clean_tui

import "core:sys/posix"

// term_state holds the saved terminal attributes so we can restore them.
@(private="file")
g_saved:  posix.termios
@(private="file")
g_in_raw: bool

// enter_raw switches stdin into "raw" mode (no echo, no canonical line
// buffering, no Ctrl-C signal generation). The caller MUST `defer restore()`
// to make sure the terminal is usable again — even on panic / early return.
//
// Returns true on success; false if stdin isn't a terminal.
enter_raw :: proc() -> bool {
	if g_in_raw {
		return true // idempotent
	}

	saved: posix.termios
	if posix.tcgetattr(posix.STDIN_FILENO, &saved) != .OK {
		return false
	}
	g_saved = saved

	raw := saved
	// Disable canonical mode, echo, and signal-generating chars so Ctrl-C
	// arrives as a regular byte (0x03) that we handle in-app.
	raw.c_lflag -= {.ICANON, .ECHO, .ISIG}
	// Read returns as soon as 1 byte is available; no timeout.
	raw.c_cc[posix.Control_Char.VMIN]  = 1
	raw.c_cc[posix.Control_Char.VTIME] = 0

	if posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw) != .OK {
		return false
	}
	g_in_raw = true
	return true
}

// restore puts stdin back into the mode it was in before enter_raw().
restore :: proc() {
	if !g_in_raw {
		return
	}
	posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &g_saved)
	g_in_raw = false
}

// read_key reads one logical key. Returns a high-level Key code. Escape
// sequences (arrow keys) are decoded here.
Key :: enum {
	Unknown,
	Char,        // see last_char
	Enter,
	Space,
	Backspace,
	Tab,
	Esc,
	Up, Down, Left, Right,
	Ctrl_C,
	Ctrl_D,
}

@(private="file")
g_last_char: u8

last_char :: proc() -> u8 {
	return g_last_char
}

read_key :: proc() -> Key {
	buf: [1]u8
	n, _ := read_stdin(buf[:])
	if n == 0 {
		return .Unknown
	}
	b := buf[0]

	switch b {
	case 0x03: return .Ctrl_C
	case 0x04: return .Ctrl_D
	case 0x09: return .Tab
	case 0x0a, 0x0d: return .Enter
	case 0x20: return .Space
	case 0x7f, 0x08: return .Backspace
	case 0x1b:
		return read_escape_sequence()
	}
	g_last_char = b
	return .Char
}

@(private="file")
read_escape_sequence :: proc() -> Key {
	buf: [2]u8
	// After ESC, expect '[' then one of 'A'/'B'/'C'/'D'. If nothing
	// follows quickly, it was a plain ESC keypress.
	n, _ := read_stdin(buf[:])
	if n < 2 {
		return .Esc
	}
	if buf[0] != '[' {
		return .Esc
	}
	switch buf[1] {
	case 'A': return .Up
	case 'B': return .Down
	case 'C': return .Right
	case 'D': return .Left
	}
	return .Unknown
}

@(private="file")
read_stdin :: proc(buf: []u8) -> (n: int, ok: bool) {
	rn := posix.read(posix.STDIN_FILENO, raw_data(buf), len(buf))
	if rn < 0 {
		return 0, false
	}
	return int(rn), true
}
