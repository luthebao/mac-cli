package clean_scan

import "base:runtime"
import "mc:clean/types"

trash_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	return scan_paths(types.category_of(.Trash), []PathSpec{
		{path = "~/.Trash", children = true},
	}, allocator)
}

trash_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Trash), items, dry_run, allocator)
}
