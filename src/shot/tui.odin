package shot

import "core:fmt"
import "core:strings"

import tui "mc:clean/tui"
import "mc:util"

// MAX_VISIBLE_ROWS caps how many apps are shown at once so the picker doesn't
// outgrow short terminals. A window slides over the filtered list as the
// user navigates.
@(private="file") MAX_VISIBLE_ROWS :: 12

// pick_app shows an interactive picker. The user types to filter the list
// (case-insensitive prefix match on app name), uses ↑/↓ to move, ⏎ to
// select. Returns the chosen App on Enter, or ok=false on Esc/Ctrl-C.
//
// When stdin is not a TTY (e.g. piped), we cannot read keys — fall back
// to picking the first app so non-interactive callers still get something.
pick_app :: proc(apps: []App) -> (chosen: App, ok: bool) {
	if len(apps) == 0 {
		return App{}, false
	}
	if !tui.enter_raw() {
		return apps[0], true
	}
	defer tui.restore()
	tui.hide_cursor()
	defer tui.show_cursor()

	filter_buf: [128]u8
	filter_len := 0
	cursor := 0
	last_lines := 0

	for {
		filter := string(filter_buf[:filter_len])
		matches := filter_apps(apps, filter, context.temp_allocator)

		if cursor >= len(matches) { cursor = max(len(matches) - 1, 0) }
		if cursor < 0             { cursor = 0 }

		tui.clear_lines(last_lines)
		last_lines = render_picker(filter, matches, cursor)

		k := tui.read_key()
		#partial switch k {
		case .Up:
			if len(matches) > 0 {
				cursor = (cursor - 1 + len(matches)) % len(matches)
			}
		case .Down:
			if len(matches) > 0 {
				cursor = (cursor + 1) % len(matches)
			}
		case .Backspace:
			if filter_len > 0 {
				filter_len -= 1
				cursor = 0
			}
		case .Char:
			c := tui.last_char()
			// Accept printable ASCII into the filter buffer. We deliberately
			// don't support multi-byte input — app names are usually ASCII
			// and adding UTF-8 entry would complicate the buffer.
			if filter_len < len(filter_buf) && c >= 0x20 && c < 0x7f {
				filter_buf[filter_len] = c
				filter_len += 1
				cursor = 0
			}
		case .Space:
			if filter_len < len(filter_buf) {
				filter_buf[filter_len] = ' '
				filter_len += 1
				cursor = 0
			}
		case .Enter:
			tui.clear_lines(last_lines)
			if len(matches) == 0 {
				return App{}, false
			}
			return matches[cursor], true
		case .Esc, .Ctrl_C, .Ctrl_D:
			tui.clear_lines(last_lines)
			return App{}, false
		}
	}
}

// filter_apps returns the subset of apps whose name (lowercased) starts
// with the filter. Empty filter passes everything through unchanged.
@(private)
filter_apps :: proc(apps: []App, filter: string, allocator := context.allocator) -> []App {
	if filter == "" {
		return apps
	}
	lf := strings.to_lower(filter, allocator)
	out := make([dynamic]App, 0, len(apps), allocator)
	for a in apps {
		ln := strings.to_lower(a.name, allocator)
		if strings.has_prefix(ln, lf) {
			append(&out, a)
		}
	}
	return out[:]
}

// render_picker prints the picker frame and returns how many terminal
// lines were emitted, so the next iteration can clear them all.
@(private)
render_picker :: proc(filter: string, matches: []App, cursor: int) -> int {
	fmt.println(util.bold("Pick an app to screenshot"))

	filter_line: string
	if filter == "" {
		filter_line = util.dim("(type to filter — prefix match)", context.temp_allocator)
	} else {
		filter_line = util.cyan(filter, context.temp_allocator)
	}
	fmt.printfln("  filter: %s", filter_line)
	fmt.println()
	lines := 3

	if len(matches) == 0 {
		fmt.println(util.dim("  (no matches)", context.temp_allocator))
		fmt.println(util.dim("↑↓ navigate · type to filter · ⌫ delete · ⏎ select · Esc cancel", context.temp_allocator))
		return lines + 2
	}

	start, end := window_around(cursor, len(matches), MAX_VISIBLE_ROWS)
	for i in start..<end {
		a := matches[i]
		marker := "  "
		if i == cursor {
			marker = util.cyan("→ ", context.temp_allocator)
		}
		pid_str := fmt.aprintf("%d", a.pid, allocator = context.temp_allocator)
		row := fmt.aprintf("%s%-6s  %s", marker, pid_str, a.name, allocator = context.temp_allocator)
		fmt.println(row)
		lines += 1
	}
	if len(matches) > MAX_VISIBLE_ROWS {
		more := fmt.aprintf("  showing %d–%d of %d", start+1, end, len(matches), allocator = context.temp_allocator)
		fmt.println(util.dim(more, context.temp_allocator))
		lines += 1
	}
	fmt.println(util.dim("↑↓ navigate · type to filter · ⌫ delete · ⏎ select · Esc cancel", context.temp_allocator))
	return lines + 1
}

// window_around picks a [start, end) slice of length ≤ max_visible that
// keeps `cursor` centered when possible, clamped to [0, n].
@(private)
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
