package clean_scan

import "base:runtime"
import "core:os"
import "core:strings"

import "mc:clean/types"
import "mc:fsx"

// /Library/Caches contents — readable without sudo on most macOS installs,
// but deletion requires sudo because subdirs are owned by root / _spotlight.
// Items are tagged requires_sudo so clean_items batches a single password
// prompt at delete time.
system_cache_root_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	cat := types.category_of(.System_Cache_Root)
	items := make([dynamic]types.CleanableItem, 0, 32, allocator)
	total: i64 = 0

	root := "/Library/Caches"
	entries, err := os.read_directory_by_path(root, -1, context.temp_allocator)
	if err != nil {
		return types.ScanResult{ category = cat }
	}
	for e in entries {
		size := e.size
		if e.type == .Directory {
			size, _ = fsx.dir_size(e.fullpath)
		}
		if size <= 0 {
			continue
		}
		append(&items, types.CleanableItem{
			path              = strings.clone(e.fullpath, allocator),
			name              = strings.clone(e.name, allocator),
			size              = size,
			is_directory      = e.type == .Directory,
			modification_time = e.modification_time,
			requires_sudo     = true,
		})
		total += size
	}
	return types.ScanResult{ category = cat, items = items[:], total_size = total }
}

system_cache_root_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.System_Cache_Root), items, dry_run, allocator)
}
