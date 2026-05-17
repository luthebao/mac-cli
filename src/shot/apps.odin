package shot

import "core:fmt"
import "core:strconv"
import "core:strings"

import "mc:sysx"

App :: struct {
	pid:  int,
	name: string,
}

// AppleScript that prints "<pid>\t<name>\n" for every foreground (non-background-only)
// application process. Multi-line literal — `osascript` runs it as one block.
@(private="file")
LIST_SCRIPT :: `tell application "System Events"
set output to ""
repeat with p in (every application process where background only is false)
set output to output & ((unix id of p) as text) & tab & (name of p) & linefeed
end repeat
return output
end tell`

// list_apps queries macOS for running GUI applications. Background-only
// processes (LaunchDaemons, helpers without UI) are excluded.
list_apps :: proc(allocator := context.allocator) -> (apps: []App, ok: bool) {
	r := sysx.run_capture({"osascript", "-e", LIST_SCRIPT}, context.temp_allocator)
	if !r.ok {
		return nil, false
	}

	buf := make([dynamic]App, 0, 32, allocator)
	lines := strings.split_lines(r.stdout, context.temp_allocator)
	for raw_line in lines {
		line := strings.trim_space(raw_line)
		if line == "" {
			continue
		}
		tab := strings.index_byte(line, '\t')
		if tab < 0 {
			continue
		}
		pid, parse_ok := strconv.parse_int(strings.trim_space(line[:tab]))
		if !parse_ok || pid <= 0 {
			continue
		}
		name := strings.clone(strings.trim_space(line[tab+1:]), allocator)
		if name == "" {
			continue
		}
		append(&buf, App{pid = pid, name = name})
	}
	return buf[:], true
}

// activate_pid asks System Events to make the process frontmost. On macOS,
// activating an app whose frontmost window lives on another Space causes
// the OS to switch to that Space — which is what we want so the window
// becomes "on screen" for CGWindowListCopyWindowInfo.
//
// We `set frontmost` (not `activate`) because activate requires knowing the
// app's bundle id; frontmost works directly from the PID.
activate_pid :: proc(pid: int) -> bool {
	script := fmt.aprintf(
		`tell application "System Events" to set frontmost of (first process whose unix id is %d) to true`,
		pid,
		allocator = context.temp_allocator,
	)
	return sysx.run_quiet({"osascript", "-e", script})
}

