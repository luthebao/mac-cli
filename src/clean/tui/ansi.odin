package clean_tui

import "core:fmt"

// ANSI cursor + line control. We don't generally need exotic stuff —
// just move/hide/show cursor and clear lines for redraw.
CSI_HIDE_CURSOR :: "\x1b[?25l"
CSI_SHOW_CURSOR :: "\x1b[?25h"
CSI_CLEAR_LINE  :: "\x1b[2K"
CSI_CLEAR_DOWN  :: "\x1b[J"
CSI_HOME_COL    :: "\r"

// cursor_up emits the escape to move N lines up. N=0 is a no-op.
cursor_up :: proc(n: int) {
	if n <= 0 {
		return
	}
	fmt.printf("\x1b[%dA", n)
}

cursor_down :: proc(n: int) {
	if n <= 0 {
		return
	}
	fmt.printf("\x1b[%dB", n)
}

hide_cursor :: proc() { fmt.print(CSI_HIDE_CURSOR) }
show_cursor :: proc() { fmt.print(CSI_SHOW_CURSOR) }

// Alternate screen buffer — used by full-screen, self-refreshing views (e.g.
// `clean monitor`) so the dashboard doesn't scroll the user's scrollback and
// the original terminal contents reappear untouched on exit.
CSI_ALT_ON  :: "\x1b[?1049h"
CSI_ALT_OFF :: "\x1b[?1049l"
CSI_HOME    :: "\x1b[H"

enter_alt :: proc() { fmt.print(CSI_ALT_ON) }
leave_alt :: proc() { fmt.print(CSI_ALT_OFF) }

// home_clear moves the cursor to the top-left. Pair with printing a full frame
// followed by clear_down() to overwrite the previous frame without the flicker
// of a full clear-screen.
home_clear :: proc() { fmt.print(CSI_HOME) }
clear_down :: proc() { fmt.print(CSI_CLEAR_DOWN) }

// clear_lines moves up `n` lines and clears them — used to redraw a
// fixed-size widget without scrolling the terminal.
clear_lines :: proc(n: int) {
	if n <= 0 {
		return
	}
	for i in 0..<n {
		fmt.print(CSI_HOME_COL)
		fmt.print(CSI_CLEAR_LINE)
		if i < n - 1 {
			cursor_up(1)
		}
	}
	fmt.print(CSI_HOME_COL)
}
