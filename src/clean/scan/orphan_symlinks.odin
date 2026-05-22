package clean_scan

import "base:runtime"
import "core:os"
import "core:strings"

import "mc:clean/types"
import "mc:fsx"

@(private="file")
ORPHAN_SYMLINK_DIRS := [?]string{
	"/opt/homebrew/bin",
	"~/.local/bin",
	"~/bin",
}

// orphan_symlinks_scan finds symlinks whose target no longer exists in the
// configured bin dirs. Deletion only removes the symlink itself (one inode),
// so size accounting is zero — items are surfaced for tidiness rather than
// space reclaim.
orphan_symlinks_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	cat := types.category_of(.Orphan_Symlinks)
	items := make([dynamic]types.CleanableItem, 0, 16, allocator)

	for raw_dir in ORPHAN_SYMLINK_DIRS {
		dir := fsx.expand(raw_dir, context.temp_allocator)
		entries, err := os.read_directory_by_path(dir, -1, context.temp_allocator)
		if err != nil {
			continue
		}
		for e in entries {
			// read_directory_by_path follows symlinks for the .type field,
			// so a dangling symlink may report as a non-existent file. Use
			// lstat to confirm it's a symlink, then stat to check the target.
			li, lerr := os.lstat(e.fullpath, context.temp_allocator)
			if lerr != nil {
				continue
			}
			if li.type != .Symlink {
				continue
			}
			if _, terr := os.stat(e.fullpath, context.temp_allocator); terr == nil {
				continue // target exists — not orphan
			}
			append(&items, types.CleanableItem{
				path         = strings.clone(e.fullpath, allocator),
				name         = strings.clone(e.name, allocator),
				size         = 0,
				is_directory = false,
			})
		}
	}
	return types.ScanResult{ category = cat, items = items[:] }
}

orphan_symlinks_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Orphan_Symlinks), items, dry_run, allocator)
}
