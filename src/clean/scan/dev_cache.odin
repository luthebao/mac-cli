package clean_scan

import "base:runtime"
import "mc:clean/types"

dev_cache_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	return scan_paths(types.category_of(.Dev_Cache), []PathSpec{
		{path = "~/Library/Developer/Xcode/DerivedData"},
		{path = "~/Library/Developer/Xcode/Archives"},
		{path = "~/Library/Developer/CoreSimulator/Caches"},
		{path = "~/Library/Caches/CocoaPods"},
		{path = "~/.npm/_cacache"},
		{path = "~/.yarn/cache"},
		{path = "~/.pnpm-store"},
		{path = "~/.cargo/registry"},
		{path = "~/.gradle/caches"},
		{path = "~/.cache/pip"},
		{path = "~/.bundle/cache"},
	}, allocator)
}

dev_cache_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Dev_Cache), items, dry_run, allocator)
}
