package fsx

import "core:fmt"
import "core:os"
import "core:testing"

@(test)
test_is_path_safe_rejects_etc :: proc(t: ^testing.T) {
	testing.expect(t, !is_path_safe("/etc/hosts"), "must refuse /etc/hosts")
}

@(test)
test_is_path_safe_rejects_root :: proc(t: ^testing.T) {
	testing.expect(t, !is_path_safe("/"), "must refuse /")
}

@(test)
test_is_path_safe_rejects_relative :: proc(t: ^testing.T) {
	testing.expect(t, !is_path_safe("../etc/hosts"), "must refuse relative paths")
	testing.expect(t, !is_path_safe("relative/path"), "must refuse relative paths")
}

@(test)
test_is_path_safe_rejects_applications :: proc(t: ^testing.T) {
	testing.expect(t, !is_path_safe("/Applications/Safari.app"), "must refuse /Applications/*")
}

@(test)
test_is_path_safe_rejects_safe_root_itself :: proc(t: ^testing.T) {
	testing.expect(t, !is_path_safe("/tmp"), "must refuse the safe root itself")
}

@(test)
test_is_path_safe_accepts_under_tmp :: proc(t: ^testing.T) {
	testing.expect(t, is_path_safe("/tmp/something"), "must allow /tmp/something")
}

@(test)
test_is_path_safe_accepts_under_home_cache :: proc(t: ^testing.T) {
	h := os.get_env("HOME", context.temp_allocator)
	if h == "" {
		return
	}
	p := fmt.aprintf("%s/Library/Caches/com.apple.foo/Cache", h, allocator = context.temp_allocator)
	testing.expect(t, is_path_safe(p), "must allow ~/Library/Caches/*")
}

@(test)
test_is_path_safe_rejects_prefix_lookalike :: proc(t: ^testing.T) {
	// `/tmpfoo` should NOT be considered under `/tmp`.
	testing.expect(t, !is_path_safe("/tmpfoo/x"), "must reject prefix-lookalike paths")
}

@(test)
test_safe_delete_refuses_unsafe :: proc(t: ^testing.T) {
	freed, err := safe_delete("/etc/hosts")
	testing.expect_value(t, freed, i64(0))
	testing.expect_value(t, err, DeleteError.Path_Not_Safe)
}
