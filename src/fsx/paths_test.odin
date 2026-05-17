package fsx

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_expand_no_tilde :: proc(t: ^testing.T) {
	got := expand("/tmp/foo")
	testing.expect_value(t, got, "/tmp/foo")
}

@(test)
test_expand_only_tilde :: proc(t: ^testing.T) {
	h := os.get_env("HOME", context.temp_allocator)
	if h == "" {
		return
	}
	got := expand("~")
	testing.expect_value(t, got, h)
}

@(test)
test_expand_tilde_slash :: proc(t: ^testing.T) {
	h := os.get_env("HOME", context.temp_allocator)
	if h == "" {
		return
	}
	got := expand("~/foo/bar")
	want := strings.concatenate({h, "/foo/bar"}, context.temp_allocator)
	testing.expect_value(t, got, want)
}

@(test)
test_abbreviate_under_home :: proc(t: ^testing.T) {
	h := os.get_env("HOME", context.temp_allocator)
	if h == "" {
		return
	}
	in_path := strings.concatenate({h, "/Documents"}, context.temp_allocator)
	got := abbreviate(in_path)
	testing.expect_value(t, got, "~/Documents")
}

@(test)
test_abbreviate_outside_home :: proc(t: ^testing.T) {
	got := abbreviate("/etc/hosts")
	testing.expect_value(t, got, "/etc/hosts")
}
