package clean_scan

import "core:testing"

@(test)
test_parse_human_size_bytes :: proc(t: ^testing.T) {
	testing.expect_value(t, parse_human_size("100B"), i64(100))
}

@(test)
test_parse_human_size_kb :: proc(t: ^testing.T) {
	testing.expect_value(t, parse_human_size("12KB"), i64(12 * 1024))
	testing.expect_value(t, parse_human_size("64K"), i64(64 * 1024))
}

@(test)
test_parse_human_size_mb :: proc(t: ^testing.T) {
	testing.expect_value(t, parse_human_size("345MB"), i64(345 * 1024 * 1024))
}

@(test)
test_parse_human_size_gb_fractional :: proc(t: ^testing.T) {
	// 1.2 GB = 1.2 * 1024^3 = 1288490188 bytes
	testing.expect_value(t, parse_human_size("1.2GB"), i64(1288490188))
}

@(test)
test_parse_human_size_with_spaces :: proc(t: ^testing.T) {
	// Some brew versions print "12.3 MB" with a space.
	// 12.3 * 1024 * 1024 = 12897484.8, truncated to 12897484 by i64() cast.
	testing.expect_value(t, parse_human_size("12.3 MB"), i64(12897484))
}

@(test)
test_parse_human_size_invalid :: proc(t: ^testing.T) {
	testing.expect_value(t, parse_human_size(""), i64(0))
	testing.expect_value(t, parse_human_size("not-a-size"), i64(0))
}

@(test)
test_parse_brew_cleanup_size_real_output :: proc(t: ^testing.T) {
	// Captured verbatim from `brew cleanup -n --prune=all` on 2026-05-22, brew 5.1.12.
	sample := `Would remove: /Users/luthebao/Library/Logs/Homebrew/uv (64B)
Would remove: /Users/luthebao/Library/Logs/Homebrew/shellcheck (64B)
Would remove: /Users/luthebao/Library/Logs/Homebrew/tmux (64B)
Would remove: /Users/luthebao/Library/Logs/Homebrew/libusb (64B)
==> This operation would free approximately 41.6MB of disk space.
`
	got := parse_brew_cleanup_size(sample)
	// 41.6 * 1024 * 1024 = 43620761.6, truncated to 43620761.
	want := i64(43620761)
	testing.expect_value(t, got, want)
}

@(test)
test_parse_brew_cleanup_size_missing :: proc(t: ^testing.T) {
	// No "approximately" line — brew sometimes runs with nothing to free.
	sample := "==> No outdated dependents to upgrade.\n"
	testing.expect_value(t, parse_brew_cleanup_size(sample), i64(0))
}

@(test)
test_parse_brew_autoremove_packages :: proc(t: ^testing.T) {
	sample := `==> Would autoremove these unused formulae:
foo bar baz
`
	pkgs := parse_brew_autoremove_packages(sample, context.allocator)
	defer delete(pkgs)
	testing.expect_value(t, len(pkgs), 3)
	testing.expect_value(t, pkgs[0], "foo")
	testing.expect_value(t, pkgs[1], "bar")
	testing.expect_value(t, pkgs[2], "baz")
}

@(test)
test_parse_brew_autoremove_packages_empty :: proc(t: ^testing.T) {
	// brew autoremove --dry-run prints nothing when there's nothing to remove.
	pkgs := parse_brew_autoremove_packages("", context.allocator)
	defer delete(pkgs)
	testing.expect_value(t, len(pkgs), 0)
}
