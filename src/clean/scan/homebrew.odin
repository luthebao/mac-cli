package clean_scan

import "base:runtime"
import "core:strings"

import "mc:clean/types"
import "mc:sysx"

homebrew_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	cat := types.category_of(.Homebrew)
	brew := find_brew()
	if brew == "" {
		return types.ScanResult{ category = cat }
	}
	res := sysx.run_capture({brew, "--cache"}, context.temp_allocator)
	if !res.ok || strings.trim_space(res.stdout) == "" {
		return types.ScanResult{ category = cat }
	}
	cache_dir := strings.trim_space(res.stdout)

	// children=true surfaces every top-level entry of the cache dir
	// (including downloads/) as its own item — no extra roll-up needed;
	// adding one would double-count downloads/ in total_size.
	specs := []PathSpec{
		{path = cache_dir, children = true},
	}
	return scan_paths(cat, specs, allocator)
}

homebrew_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Homebrew), items, dry_run, allocator)
}
