package clean_scan

import "base:runtime"
import "mc:clean/types"

mail_attachments_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	return scan_paths(types.category_of(.Mail_Attachments), []PathSpec{
		{path = "~/Library/Mail/Downloads", children = true},
	}, allocator)
}

mail_attachments_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Mail_Attachments), items, dry_run, allocator)
}
