package fsx

import "core:testing"

@(test)
test_format_size_zero :: proc(t: ^testing.T) {
	got := format_size(0)
	testing.expect_value(t, got, "0 B")
}

@(test)
test_format_size_bytes :: proc(t: ^testing.T) {
	got := format_size(512)
	testing.expect_value(t, got, "512 B")
}

@(test)
test_format_size_kilobytes :: proc(t: ^testing.T) {
	got := format_size(1024)
	testing.expect_value(t, got, "1.0 KB")
}

@(test)
test_format_size_megabytes :: proc(t: ^testing.T) {
	got := format_size(1_572_864) // 1.5 MiB
	testing.expect_value(t, got, "1.5 MB")
}

@(test)
test_format_size_gigabytes :: proc(t: ^testing.T) {
	got := format_size(2_147_483_648) // 2 GiB
	testing.expect_value(t, got, "2.0 GB")
}

@(test)
test_format_size_negative :: proc(t: ^testing.T) {
	got := format_size(-1)
	testing.expect_value(t, got, "0 B")
}
