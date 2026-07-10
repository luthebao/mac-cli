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
test_is_path_safe_leaf_roots_deletable_whole :: proc(t: ^testing.T) {
	h := os.get_env("HOME", context.temp_allocator)
	if h == "" {
		return
	}
	// Pure caches surfaced as a single item (path == root) must be deletable.
	for rel in ([?]string{
		"/.cargo/registry",
		"/.gradle/caches",
		"/.bundle/cache",
		"/.pnpm-store",
		"/Library/Developer/Xcode/DerivedData",
		"/Library/Developer/Xcode/Archives",
		"/Library/Developer/CoreSimulator/Caches",
	}) {
		p := fmt.aprintf("%s%s", h, rel, allocator = context.temp_allocator)
		testing.expect(t, is_path_safe(p), fmt.tprintf("leaf cache must be deletable: %s", p))
	}
}

@(test)
test_is_path_safe_broad_roots_not_deletable_whole :: proc(t: ^testing.T) {
	h := os.get_env("HOME", context.temp_allocator)
	if h == "" {
		return
	}
	// Containers that also hold user data must still refuse wholesale deletion.
	for rel in ([?]string{"/Downloads", "/Library/Caches", "/Library/Logs", "/.Trash", "/.cargo"}) {
		p := fmt.aprintf("%s%s", h, rel, allocator = context.temp_allocator)
		testing.expect(t, !is_path_safe(p), fmt.tprintf("broad container must NOT be deletable whole: %s", p))
	}
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
test_wildcard_leaf_cache_dir_deletable :: proc(t: ^testing.T) {
	h := os.get_env("HOME", context.temp_allocator)
	if h == "" {
		return
	}
	// The App Caches scanner surfaces these cache dirs themselves (path ==
	// wildcard pattern). They are leaf caches → must be deletable wholesale.
	for rel in ([?]string{
		"/Library/Application Support/discord/Cache",
		"/Library/Application Support/discord/Code Cache",
		"/Library/Application Support/discord/GPUCache",
		"/Library/Application Support/discord/Service Worker/CacheStorage",
	}) {
		p := fmt.aprintf("%s%s", h, rel, allocator = context.temp_allocator)
		testing.expect(t, is_path_safe(p), fmt.tprintf("leaf cache dir must be deletable: %s", p))
	}
}

@(test)
test_wildcard_non_leaf_root_still_refused :: proc(t: ^testing.T) {
	// Non-leaf wildcard root (.Trashes) is still refused at the dir itself;
	// only entries strictly inside it are allowed.
	testing.expect(t, !is_path_safe("/Volumes/MyDisk/.Trashes"), "must refuse the .Trashes dir itself")
	testing.expect(t, is_path_safe("/Volumes/MyDisk/.Trashes/501/x"), "must allow entries inside .Trashes")
}

@(test)
test_is_path_safe_reviewed :: proc(t: ^testing.T) {
	h := os.get_env("HOME", context.temp_allocator)
	if h == "" {
		return
	}
	// A hand-picked large file anywhere under $HOME is deletable when reviewed,
	// even though it's outside the strict cache allowlist.
	big := fmt.aprintf("%s/Library/Application Support/Claude/vm_bundles/rootfs.img", h, allocator = context.temp_allocator)
	testing.expect(t, !is_path_safe(big), "strict allowlist refuses arbitrary app-support files")
	testing.expect(t, is_path_safe_reviewed(big), "reviewed gate allows hand-picked $HOME files")

	// But never $HOME itself, paths outside $HOME, or protected system paths.
	testing.expect(t, !is_path_safe_reviewed(h), "must refuse $HOME itself")
	testing.expect(t, !is_path_safe_reviewed("/System/Library/foo"), "must refuse system paths")
	testing.expect(t, !is_path_safe_reviewed("/etc/hosts"), "must refuse /etc")
	testing.expect(t, !is_path_safe_reviewed("/var/big.log"), "must refuse outside $HOME")
}

@(test)
test_var_folders_both_spellings_safe :: proc(t: ^testing.T) {
	// macOS mounts /var → /private/var; the temp-files scanner and $TMPDIR
	// produce the /var spelling. Both must be judged identically, and
	// DANGER_PATHS' /var entry must not shadow the safe root (a regression
	// that once made the whole Temp Files category refuse to clean).
	testing.expect(t, is_path_safe("/var/folders/x1/y2/T/cache.db"), "must allow /var/folders/…")
	testing.expect(t, is_path_safe("/private/var/folders/x1/y2/T/cache.db"), "must allow /private/var/folders/…")
	// The rest of /var stays refused.
	testing.expect(t, !is_path_safe("/var/db/foo"), "must refuse /var/db")
	testing.expect(t, !is_path_safe("/var/root/x"), "must refuse /var/root")
	testing.expect(t, !is_path_safe("/var/folders"), "must refuse the root itself")
}

@(test)
test_chrome_profile_cache_deletable :: proc(t: ^testing.T) {
	h := os.get_env("HOME", context.temp_allocator)
	if h == "" {
		return
	}
	// Chrome nests per-profile caches one level deeper than the generic
	// Electron pattern; the browser-cache scanner surfaces the dir itself.
	p := fmt.aprintf("%s/Library/Application Support/Google/Chrome/Default/Cache", h, allocator = context.temp_allocator)
	testing.expect(t, is_path_safe(p), "must allow Chrome per-profile Cache dirs")
	other := fmt.aprintf("%s/Library/Application Support/Google/Chrome/Default/Bookmarks", h, allocator = context.temp_allocator)
	testing.expect(t, !is_path_safe(other), "must refuse non-cache Chrome profile data")
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
