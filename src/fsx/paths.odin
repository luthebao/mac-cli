package fsx

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// home returns $HOME or empty string if unset. Always returns a freshly
// allocated string (or "").
home :: proc(allocator := context.allocator) -> string {
	return os.get_env("HOME", allocator)
}

// expand expands a leading `~` to $HOME. Caller owns the returned string.
expand :: proc(path: string, allocator := context.allocator) -> string {
	if !strings.has_prefix(path, "~") {
		return strings.clone(path, allocator)
	}

	h := home(context.temp_allocator)
	if h == "" {
		return strings.clone(path, allocator)
	}
	if path == "~" {
		return strings.clone(h, allocator)
	}
	if strings.has_prefix(path, "~/") {
		joined, _ := filepath.join({h, path[2:]}, allocator)
		return joined
	}
	return strings.clone(path, allocator)
}

// abbreviate replaces a leading $HOME with `~`. Caller owns the returned string.
abbreviate :: proc(path: string, allocator := context.allocator) -> string {
	h := home(context.temp_allocator)
	if h == "" || !strings.has_prefix(path, h) {
		return strings.clone(path, allocator)
	}
	if path == h {
		return strings.clone("~", allocator)
	}
	// path[len(h)] is the next char after $HOME. If it's not '/', it's a
	// path like /home/usernamesomething — not an actual $HOME prefix.
	if len(path) > len(h) && path[len(h)] != '/' {
		return strings.clone(path, allocator)
	}
	return fmt.aprintf("~%s", path[len(h):], allocator = allocator)
}

// join_home joins $HOME with the given segments. Convenience wrapper.
join_home :: proc(segments: ..string, allocator := context.allocator) -> string {
	h := home(context.temp_allocator)
	if h == "" {
		joined, _ := filepath.join(segments, allocator)
		return joined
	}
	parts := make([dynamic]string, 0, len(segments) + 1, context.temp_allocator)
	append(&parts, h)
	for s in segments {
		append(&parts, s)
	}
	joined, _ := filepath.join(parts[:], allocator)
	return joined
}
