package fsx

import "core:fmt"
import "core:strings"

// format_size returns a human-readable byte count using IEC 1024-based units
// with one decimal place — matches what most macOS-facing tools display.
// Example: format_size(1_572_864) → "1.5 MB"
format_size :: proc(bytes: i64, allocator := context.allocator) -> string {
	if bytes < 0 {
		return strings.clone("0 B", allocator)
	}
	if bytes < 1024 {
		return fmt.aprintf("%d B", bytes, allocator = allocator)
	}

	units := [?]string{"KB", "MB", "GB", "TB", "PB"}
	size := f64(bytes)
	idx := 0
	size /= 1024 // first promotion: B → KB

	for size >= 1024 && idx < len(units) - 1 {
		size /= 1024
		idx += 1
	}

	return fmt.aprintf("%.1f %s", size, units[idx], allocator = allocator)
}
