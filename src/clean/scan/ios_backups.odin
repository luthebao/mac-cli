package clean_scan

import "base:runtime"
import "mc:clean/types"

ios_backups_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	return scan_paths(types.category_of(.Ios_Backups), []PathSpec{
		{path = "~/Library/Application Support/MobileSync/Backup", children = true},
	}, allocator)
}

ios_backups_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Ios_Backups), items, dry_run, allocator)
}
