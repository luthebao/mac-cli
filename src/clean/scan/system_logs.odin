package clean_scan

import "base:runtime"
import "mc:clean/types"

system_logs_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	return scan_paths(types.category_of(.System_Logs), []PathSpec{
		{path = "~/Library/Logs", children = true},
		{path = "/Library/Logs", children = true},
	}, allocator)
}

system_logs_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.System_Logs), items, dry_run, allocator)
}
