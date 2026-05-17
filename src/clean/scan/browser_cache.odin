package clean_scan

import "base:runtime"
import "mc:clean/types"

browser_cache_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	return scan_paths(types.category_of(.Browser_Cache), []PathSpec{
		// Chrome
		{path = "~/Library/Caches/Google/Chrome"},
		{path = "~/Library/Application Support/Google/Chrome/Default/Cache"},
		// Safari
		{path = "~/Library/Caches/com.apple.Safari"},
		{path = "~/Library/Caches/com.apple.WebKit.PluginProcess"},
		// Firefox
		{path = "~/Library/Caches/Firefox"},
		// Arc
		{path = "~/Library/Caches/Company.ThatBrowserCompany.Browser"},
		// Brave
		{path = "~/Library/Caches/BraveSoftware"},
		// Edge
		{path = "~/Library/Caches/Microsoft Edge"},
	}, allocator)
}

browser_cache_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Browser_Cache), items, dry_run, allocator)
}
