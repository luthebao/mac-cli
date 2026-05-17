package clean_scan

import "base:runtime"
import "core:os"
import "core:strings"
import "core:time"

import "mc:clean/types"
import "mc:fsx"

downloads_scan :: proc(opts: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	cat := types.category_of(.Downloads)
	days := opts.days_old
	if days <= 0 {
		days = 30
	}

	items := make([dynamic]types.CleanableItem, 0, 16, allocator)
	total: i64 = 0

	downloads_dir := fsx.expand("~/Downloads", context.temp_allocator)
	entries, err := os.read_directory_by_path(downloads_dir, -1, context.temp_allocator)
	if err != nil {
		return types.ScanResult{ category = cat }
	}

	now := time.now()
	threshold := time.Duration(days) * 24 * time.Hour

	for e in entries {
		age := time.diff(e.modification_time, now)
		if age < threshold {
			continue
		}
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
		})
		total += size
	}

	return types.ScanResult{
		category   = cat,
		items      = items[:],
		total_size = total,
	}
}

downloads_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Downloads), items, dry_run, allocator)
}
