package clean_store

import "core:crypto/hash"
import "core:fmt"
import "core:os"
import "core:strings"

// sha256_file returns the lowercase hex SHA-256 digest of a file's contents.
// Returns ok=false on any read error.
sha256_file :: proc(path: string, allocator := context.allocator) -> (digest_hex: string, ok: bool) {
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil {
		return "", false
	}
	digest := hash.hash_bytes(.SHA256, data, context.temp_allocator)
	return hex_lower(digest, allocator), true
}

// sha256_bytes hashes the provided byte slice and returns lowercase hex.
sha256_bytes :: proc(data: []byte, allocator := context.allocator) -> string {
	digest := hash.hash_bytes(.SHA256, data, context.temp_allocator)
	return hex_lower(digest, allocator)
}

@(private)
hex_lower :: proc(bytes: []byte, allocator := context.allocator) -> string {
	b := strings.builder_make(0, len(bytes) * 2, allocator)
	for byte_val in bytes {
		fmt.sbprintf(&b, "%02x", byte_val)
	}
	return strings.to_string(b)
}
