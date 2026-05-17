package shot

import "core:fmt"
import "core:os"
import "core:strings"

import "mc:sysx"

// desktop_dir returns $HOME/Desktop. We don't validate it exists — if the
// user's home is missing, screencapture itself will error out with a useful
// message.
@(private)
desktop_dir :: proc(allocator := context.allocator) -> string {
	home := os.get_env("HOME", context.temp_allocator)
	return strings.concatenate({home, "/Desktop"}, allocator)
}

// timestamp_now returns a filename-safe timestamp like "20260518-143015".
// We shell out to `date` rather than wrangling core:time formatting — it's
// always present on macOS and the output is exactly what we want.
@(private)
timestamp_now :: proc(allocator := context.allocator) -> string {
	r := sysx.run_capture({"date", "+%Y%m%d-%H%M%S"}, context.temp_allocator)
	if !r.ok || r.stdout == "" {
		return strings.clone("snapshot", allocator)
	}
	return strings.clone(r.stdout, allocator)
}

// build_path composes "<Desktop>/<label>-<ts>.png".
build_path :: proc(label: string, allocator := context.allocator) -> string {
	ts := timestamp_now(context.temp_allocator)
	fname := fmt.aprintf("%s-%s.png", label, ts, allocator = context.temp_allocator)
	return strings.concatenate({desktop_dir(context.temp_allocator), "/", fname}, allocator)
}

// capture_full_screen runs `screencapture -x <path>`. -x silences the
// camera-shutter sound; format is inferred from the .png extension.
capture_full_screen :: proc(path: string) -> bool {
	return sysx.run_quiet({"screencapture", "-x", path})
}

// capture_window captures a specific window by CGWindowID.
//   -l <id>  target a window
//   -o       no drop-shadow border (clean rectangular crop)
//   -x       silent (no shutter sound)
// The window is read from its backing store, so the capture works even if
// the window is occluded or in another Space, and we don't need to activate
// the app or steal focus.
capture_window :: proc(id: CGWindowID, path: string) -> bool {
	id_str := fmt.aprintf("%d", id, allocator = context.temp_allocator)
	return sysx.run_quiet({"screencapture", "-l", id_str, "-o", "-x", path})
}

// sanitize_label keeps ASCII letters, digits, dash, and underscore; turns
// spaces into dashes; drops everything else. Used so an app name like
// "Visual Studio Code" becomes "Visual-Studio-Code" in the filename.
sanitize_label :: proc(s: string, allocator := context.allocator) -> string {
	buf := make([dynamic]u8, 0, len(s), allocator)
	for r in s {
		switch r {
		case 'a'..='z', 'A'..='Z', '0'..='9', '-', '_':
			append(&buf, u8(r))
		case ' ':
			append(&buf, '-')
		case:
			// drop punctuation, accented chars, emoji
		}
	}
	if len(buf) == 0 {
		return strings.clone("app", allocator)
	}
	return string(buf[:])
}
