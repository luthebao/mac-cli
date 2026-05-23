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

@(test)
test_wildcard_root_accepts_app_cache :: proc(t: ^testing.T) {
	h := os.get_env("HOME", context.temp_allocator)
	if h == "" {
		return
	}
	p := fmt.aprintf("%s/Library/Application Support/Slack/Cache/foo.bin", h, allocator = context.temp_allocator)
	testing.expect(t, is_path_safe(p), "must allow ~/Library/Application Support/Slack/Cache/*")
}

@(test)
test_wildcard_root_rejects_sibling_under_app_support :: proc(t: ^testing.T) {
	h := os.get_env("HOME", context.temp_allocator)
	if h == "" {
		return
	}
	// Not under any whitelisted subdir — must NOT be deletable.
	p := fmt.aprintf("%s/Library/Application Support/Slack/storage/important.db", h, allocator = context.temp_allocator)
	testing.expect(t, !is_path_safe(p), "must refuse paths outside whitelisted cache subdirs")
}

@(test)
test_wildcard_root_rejects_root_itself :: proc(t: ^testing.T) {
	h := os.get_env("HOME", context.temp_allocator)
	if h == "" {
		return
	}
	// Matching the wildcard root exactly (no strict-inside) must refuse.
	p := fmt.aprintf("%s/Library/Application Support/Slack/Cache", h, allocator = context.temp_allocator)
	testing.expect(t, !is_path_safe(p), "must refuse the wildcard root itself")
}

@(test)
test_wildcard_root_accepts_external_trash :: proc(t: ^testing.T) {
	p := "/Volumes/MyDisk/.Trashes/501/something.txt"
	testing.expect(t, is_path_safe(p), "must allow per-uid external trash entries")
}

@(test)
test_wildcard_root_rejects_non_trash_on_volume :: proc(t: ^testing.T) {
	p := "/Volumes/MyDisk/Backups/family-photos"
	testing.expect(t, !is_path_safe(p), "must refuse non-trash paths on external volumes")
}

@(test)
test_wildcard_root_accepts_brew_bin :: proc(t: ^testing.T) {
	p := "/opt/homebrew/bin/some-orphan-link"
	testing.expect(t, is_path_safe(p), "must allow /opt/homebrew/bin/* for orphan symlink cleanup")
}

@(test)
test_wildcard_root_rejects_boot_volume_system :: proc(t: ^testing.T) {
	// Removing /Volumes from DANGER_PATHS was deliberate — the boot volume is
	// still safe because no SAFE_ROOTS pattern matches paths outside .Trashes.
	testing.expect(t, !is_path_safe("/Volumes/Macintosh HD/etc/hosts"), "must refuse boot volume system paths")
	testing.expect(t, !is_path_safe("/Volumes/Macintosh HD/Users/luthebao/Documents"), "must refuse boot volume user paths")
}
