package clean_scan

import "base:runtime"
import "core:strings"

import "mc:clean/types"
import "mc:fsx"

LARGE_FILE_THRESHOLD :: 500 * 1024 * 1024 // 500 MB

large_files_scan :: proc(opts: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	cat := types.category_of(.Large_Files)
	min := opts.min_size
	if min <= 0 {
		min = LARGE_FILE_THRESHOLD
	}

	home := fsx.expand("~", context.temp_allocator)
	entries := fsx.walk_collect(home, fsx.WalkFilter{
		min_size  = min,
		max_depth = 6, // cap recursion — full $HOME scan is too slow otherwise
	}, context.temp_allocator)

	items := make([dynamic]types.CleanableItem, 0, len(entries), allocator)
	total: i64 = 0
	for e in entries {
		append(&items, types.CleanableItem{
			path              = strings.clone(e.path, allocator),
			name              = strings.clone(e.path, allocator),
			size              = e.size,
			is_directory      = e.is_dir,
			modification_time = e.modification_time,
		})
		total += e.size
	}

	return types.ScanResult{
		category   = cat,
		items      = items[:],
		total_size = total,
	}
}

large_files_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Large_Files), items, dry_run, allocator)
}
