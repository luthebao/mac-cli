package clean_scan

import "base:runtime"
import "core:os"
import "core:strings"

import "mc:clean/types"
import "mc:fsx"
import "mc:sysx"

homebrew_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	cat := types.category_of(.Homebrew)
	res := sysx.run_capture({"/opt/homebrew/bin/brew", "--cache"}, context.temp_allocator)
	if !res.ok {
		res = sysx.run_capture({"/usr/local/bin/brew", "--cache"}, context.temp_allocator)
	}
	if !res.ok || strings.trim_space(res.stdout) == "" {
		return types.ScanResult{ category = cat }
	}
	cache_dir := strings.trim_space(res.stdout)

	specs := []PathSpec{
		{path = cache_dir, children = true},
	}
	scan := scan_paths(cat, specs, allocator)

	// Roll up the downloads subdir as a single item too.
	dl := strings.concatenate({cache_dir, "/downloads"}, context.temp_allocator)
	if _, derr := os.stat(dl, context.temp_allocator); derr == nil {
		size, _ := fsx.dir_size(dl)
		if size > 0 {
			scan.total_size += size
		}
	}
	return scan
}

homebrew_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Homebrew), items, dry_run, allocator)
}
