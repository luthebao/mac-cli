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

// is_interactive reports whether stdin is a usable TTY (raw mode is available).
// Probe by entering raw mode and immediately restoring so terminal state stays
// clean. Callers use this to refuse destructive interactive flows when piped /
// non-interactive, where confirmation prompts would silently take defaults.
is_interactive :: proc() -> bool {
	if !enter_raw() {
		return false
	}
	restore()
	return true
}

// poll_key waits up to `timeout_ms` for a keypress. Returns (key, true) if one
// arrived, or (.Unknown, false) on timeout — letting a refresh loop (e.g.
// `clean monitor`) redraw on a fixed cadence while staying responsive to 'q'.
poll_key :: proc(timeout_ms: i32) -> (Key, bool) {
	if !stdin_has_input(timeout_ms) {
		return .Unknown, false
	}
	return read_key(), true
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

// read_escape_sequence handles input starting with ESC. It distinguishes:
//   - a lone ESC keypress (no bytes follow within ~50ms) → .Esc
//   - a CSI sequence `ESC [ params? intermediates? final` → decoded arrow or .Unknown
//   - an SS3 sequence `ESC O <byte>` (function keys) → .Unknown
//   - anything else following ESC → .Esc
//
// The previous version read a fixed 2 bytes after ESC, which left bytes from
// longer sequences (mouse SGR `ESC [ < … M`, modified arrows `ESC [ 1;5A`,
// any-motion mouse `ESC [ < 35;col;rowM`) in the input buffer. Those bytes
// would then be picked up as bogus .Char events, causing spurious re-renders
// (and, in some terminals, visible drift as the menu redrew on each leaked
// byte). Draining the full sequence here fixes that for every TUI caller.
@(private="file")
read_escape_sequence :: proc() -> Key {
	// Is there a next byte ready? poll() with a small timeout lets us
	// detect a lone ESC without blocking, and avoids the cliff where a
	// user presses Esc and the menu hangs waiting for more input.
	if !stdin_has_input(50) {
		return .Esc
	}
	first: [1]u8
	n, _ := read_stdin(first[:])
	if n == 0 {
		return .Esc
	}
	switch first[0] {
	case '[':
		return read_csi()
	case 'O':
		// SS3 (some terminals send F1-F4 this way). Drain one byte.
		b: [1]u8
		read_stdin(b[:])
		return .Unknown
	}
	// Other ESC-prefixed sequences (Meta+key, etc.) — treat as bare Esc.
	return .Esc
}

// read_csi parses a Control Sequence Introducer payload after the leading
// `ESC [`. Returns the matched arrow key, or .Unknown for anything else
// (the bytes are still fully consumed so they don't leak).
@(private="file")
read_csi :: proc() -> Key {
	// Read parameter bytes (0x30-0x3F) and intermediate bytes (0x20-0x2F)
	// until we hit a final byte (0x40-0x7E). We don't actually use the
	// parameters yet; modified arrows (`ESC [ 1;5A`) still decode to
	// Up/Down based on the final byte.
	final: u8 = 0
	saw_params := false
	for _ in 0..<32 {
		b: [1]u8
		// Bytes inside a CSI arrive contiguously — a short poll keeps
		// us robust against a half-delivered sequence.
		if !stdin_has_input(50) {
			break
		}
		n, _ := read_stdin(b[:])
		if n == 0 {
			break
		}
		if b[0] >= 0x40 && b[0] <= 0x7E {
			final = b[0]
			break
		}
		// param byte (0x30-0x3F) or intermediate (0x20-0x2F) — keep reading
		saw_params = true
	}
	switch final {
	case 'A': return .Up
	case 'B': return .Down
	case 'C': return .Right
	case 'D': return .Left
	case 'M':
		// `ESC [ M cb cx cy` is xterm normal mouse — 3 raw bytes follow
		// the M and need draining. The SGR form (`ESC [ < b ; col ; row M`)
		// ends at the M with no trailing bytes; if we drained 3 there we'd
		// quietly eat the user's next keypresses. The discriminator:
		// normal mouse has no parameters before M, SGR mouse always does.
		if !saw_params {
			extra: [3]u8
			read_stdin(extra[:])
		}
		return .Unknown
	}
	return .Unknown
}

// stdin_has_input returns true if at least one byte is readable from stdin
// within `timeout_ms`. Used to peek without blocking.
@(private="file")
stdin_has_input :: proc(timeout_ms: i32) -> bool {
	fds := [1]posix.pollfd{
		{fd = posix.STDIN_FILENO, events = {.IN}, revents = {}},
	}
	rc := posix.poll(&fds[0], 1, timeout_ms)
	return rc > 0 && (.IN in fds[0].revents)
}

@(private="file")
read_stdin :: proc(buf: []u8) -> (n: int, ok: bool) {
	rn := posix.read(posix.STDIN_FILENO, raw_data(buf), len(buf))
	if rn < 0 {
		return 0, false
	}
	return int(rn), true
}
