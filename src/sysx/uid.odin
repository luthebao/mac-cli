package sysx

import "core:strconv"
import "core:strings"

// geteuid returns the current effective user id, or -1 on failure.
// Implemented by shelling out to /usr/bin/id; we only call it once per scan,
// so the fork cost is negligible and we avoid platform-specific bindings.
geteuid :: proc() -> int {
	r := run_capture({"/usr/bin/id", "-u"}, context.temp_allocator)
	if !r.ok {
		return -1
	}
	uid, ok := strconv.parse_int(strings.trim_space(r.stdout))
	if !ok {
		return -1
	}
	return uid
}
