package clean_store

import "core:testing"

@(test)
test_sha256_empty :: proc(t: ^testing.T) {
	// Well-known SHA-256 of empty input.
	want := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
	got := sha256_bytes({})
	testing.expect_value(t, got, want)
}

@(test)
test_sha256_known :: proc(t: ^testing.T) {
	// SHA-256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
	want := "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	got := sha256_bytes(transmute([]byte)string("abc"))
	testing.expect_value(t, got, want)
}
