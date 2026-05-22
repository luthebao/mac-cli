package clean_scan

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

import "mc:clean/types"
import "mc:sysx"

trash_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	specs := make([dynamic]PathSpec, 0, 4, context.temp_allocator)
	append(&specs, PathSpec{path = "~/.Trash", children = true})

	// External volume trash: /Volumes/<disk>/.Trashes/<euid>
	uid := sysx.geteuid()
	if uid >= 0 {
		entries, err := os.read_directory_by_path("/Volumes", -1, context.temp_allocator)
		if err == nil {
			uid_str := fmt.tprintf("%d", uid)
			for e in entries {
				if e.type != .Directory {
					continue
				}
				candidate := strings.concatenate({e.fullpath, "/.Trashes/", uid_str}, context.temp_allocator)
				if fi, serr := os.stat(candidate, context.temp_allocator); serr == nil && fi.type == .Directory {
					append(&specs, PathSpec{path = candidate, children = true})
				}
			}
		}
	}

	return scan_paths(types.category_of(.Trash), specs[:], allocator)
}

trash_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Trash), items, dry_run, allocator)
}
