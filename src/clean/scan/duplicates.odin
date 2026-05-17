package clean_scan

import "base:runtime"
import "core:strings"
import "core:time"

import "mc:clean/store"
import "mc:clean/types"
import "mc:fsx"

DUP_MIN_SIZE :: 1024 * 1024 // 1 MB

duplicates_scan :: proc(opts: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	cat := types.category_of(.Duplicates)
	min := opts.min_size
	if min <= 0 {
		min = DUP_MIN_SIZE
	}

	// Phase 1: gather every regular file in $HOME above the min size.
	home := fsx.expand("~", context.temp_allocator)
	entries := fsx.walk_collect(home, fsx.WalkFilter{
		min_size  = min,
		max_depth = 6,
	}, context.temp_allocator)

	// Phase 2: group by size — only same-sized files can be duplicates.
	by_size: map[i64][dynamic]fsx.WalkEntry
	defer delete(by_size)
	by_size = make(map[i64][dynamic]fsx.WalkEntry, 64, context.temp_allocator)
	for e in entries {
		group, found := &by_size[e.size]
		if !found {
			arr := make([dynamic]fsx.WalkEntry, 0, 2, context.temp_allocator)
			by_size[e.size] = arr
			group = &by_size[e.size]
		}
		append(group, e)
	}

	// Phase 3: for size-groups with 2+ entries, hash and bucket by digest.
	items := make([dynamic]types.CleanableItem, 0, 16, allocator)
	total: i64 = 0
	for _, group in by_size {
		if len(group) < 2 {
			continue
		}
		by_hash: map[string][dynamic]fsx.WalkEntry
		by_hash = make(map[string][dynamic]fsx.WalkEntry, len(group), context.temp_allocator)
		for entry in group {
			digest, ok := store.sha256_file(entry.path, context.temp_allocator)
			if !ok {
				continue
			}
			arr, present := &by_hash[digest]
			if !present {
				new_arr := make([dynamic]fsx.WalkEntry, 0, 2, context.temp_allocator)
				by_hash[digest] = new_arr
				arr = &by_hash[digest]
			}
			append(arr, entry)
		}
		// Phase 4: for each hash with 2+ entries, keep the newest, mark
		// the rest as removable.
		for _, dup_set in by_hash {
			if len(dup_set) < 2 {
				continue
			}
			newest_idx := 0
			for entry, i in dup_set {
				if time.diff(dup_set[newest_idx].modification_time, entry.modification_time) > 0 {
					newest_idx = i
				}
			}
			for entry, i in dup_set {
				if i == newest_idx {
					continue
				}
				append(&items, types.CleanableItem{
					path              = strings.clone(entry.path, allocator),
					name              = strings.clone(entry.path, allocator),
					size              = entry.size,
					is_directory      = false,
					modification_time = entry.modification_time,
				})
				total += entry.size
			}
		}
	}

	return types.ScanResult{
		category   = cat,
		items      = items[:],
		total_size = total,
	}
}

duplicates_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Duplicates), items, dry_run, allocator)
}
