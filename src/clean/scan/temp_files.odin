package clean_scan

import "base:runtime"
import "mc:clean/types"

temp_files_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	return scan_paths(types.category_of(.Temp_Files), []PathSpec{
		{path = "/tmp", children = true},
		{path = "/private/tmp", children = true},
		{path = "/var/folders", children = true},
		{path = "/private/var/folders", children = true},
	}, allocator)
}

temp_files_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Temp_Files), items, dry_run, allocator)
}
