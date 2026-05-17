package util

import "core:fmt"
import "core:os"
import "core:strings"

// ANSI SGR colors. Use the `color` and `style` helpers rather than these
// constants directly — they respect `--no-color`/$NO_COLOR.
RESET     :: "\x1b[0m"
BOLD      :: "\x1b[1m"
DIM       :: "\x1b[2m"
UNDERLINE :: "\x1b[4m"

RED     :: "\x1b[31m"
GREEN   :: "\x1b[32m"
YELLOW  :: "\x1b[33m"
BLUE    :: "\x1b[34m"
MAGENTA :: "\x1b[35m"
CYAN    :: "\x1b[36m"
WHITE   :: "\x1b[37m"
GRAY    :: "\x1b[90m"

@(private)
g_color_enabled := -1 // -1 = unknown, 0 = off, 1 = on

// color_enabled reports whether ANSI escapes should be emitted.
// Disabled when $NO_COLOR is set or stdout isn't a TTY. Cached.
color_enabled :: proc() -> bool {
	if g_color_enabled >= 0 {
		return g_color_enabled == 1
	}
	if no := os.get_env("NO_COLOR", context.temp_allocator); no != "" {
		g_color_enabled = 0
		return false
	}
	// Best-effort TTY detection — Odin lacks a portable isatty wrapper in
	// `core:os`. We fall back to "on" and let the user opt out via NO_COLOR.
	g_color_enabled = 1
	return true
}

// color wraps `s` in an SGR sequence; respects color_enabled().
color :: proc(s, code: string, allocator := context.allocator) -> string {
	if !color_enabled() {
		return strings.clone(s, allocator)
	}
	return fmt.aprintf("%s%s%s", code, s, RESET, allocator = allocator)
}

red     :: proc(s: string, allocator := context.allocator) -> string { return color(s, RED, allocator) }
green   :: proc(s: string, allocator := context.allocator) -> string { return color(s, GREEN, allocator) }
yellow  :: proc(s: string, allocator := context.allocator) -> string { return color(s, YELLOW, allocator) }
blue    :: proc(s: string, allocator := context.allocator) -> string { return color(s, BLUE, allocator) }
cyan    :: proc(s: string, allocator := context.allocator) -> string { return color(s, CYAN, allocator) }
gray    :: proc(s: string, allocator := context.allocator) -> string { return color(s, GRAY, allocator) }
bold    :: proc(s: string, allocator := context.allocator) -> string { return color(s, BOLD, allocator) }
dim     :: proc(s: string, allocator := context.allocator) -> string { return color(s, DIM, allocator) }
