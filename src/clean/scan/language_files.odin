package clean_scan

import "base:runtime"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "mc:clean/types"
import "mc:fsx"

// KEEP_LANGS are .lproj entries we never report — these are typically the
// user's active locale set on macOS.
KEEP_LANGS := [?]string{"en.lproj", "English.lproj", "Base.lproj"}

language_files_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	cat := types.category_of(.Language_Files)
	items := make([dynamic]types.CleanableItem, 0, 64, allocator)
	total: i64 = 0

	roots := []string{ "/Applications" }
	for root in roots {
		find_lprojs(&items, &total, root, 0, allocator)
	}

	return types.ScanResult{
		category   = cat,
		items      = items[:],
		total_size = total,
	}
}

language_files_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Language_Files), items, dry_run, allocator)
}

@(private)
find_lprojs :: proc(out: ^[dynamic]types.CleanableItem, total: ^i64, dir: string, depth: int, allocator: runtime.Allocator) {
	if depth > 5 {
		return
	}
	entries, err := os.read_directory_by_path(dir, -1, context.temp_allocator)
	if err != nil {
		return
	}
	for e in entries {
		if e.type != .Directory {
			continue
		}
		if strings.has_suffix(e.name, ".lproj") {
			keep := false
			for k in KEEP_LANGS {
				if e.name == k {
					keep = true
					break
				}
			}
			if keep {
				continue
			}
			size, _ := fsx.dir_size(e.fullpath)
			if size <= 0 {
				continue
			}
			append(out, types.CleanableItem{
				path              = strings.clone(e.fullpath, allocator),
				name              = strings.clone(e.name, allocator),
				size              = size,
				is_directory      = true,
				modification_time = e.modification_time,
			})
			total^ += size
			continue
		}
		// Recurse into .app bundles' Contents/Resources but not anywhere else
		sub := filepath.base(e.name)
		_ = sub
		find_lprojs(out, total, e.fullpath, depth + 1, allocator)
	}
}
