package clean_scan

import "base:runtime"
import "mc:clean/types"

system_cache_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	return scan_paths(types.category_of(.System_Cache), []PathSpec{
		{path = "~/Library/Caches", children = true},
	}, allocator)
}

system_cache_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.System_Cache), items, dry_run, allocator)
}
