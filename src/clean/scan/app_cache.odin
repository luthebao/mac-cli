package clean_scan

import "base:runtime"
import "core:os"
import "core:strings"

import "mc:clean/types"
import "mc:fsx"

// Known cache subdir names that Electron / Chromium-based apps drop into
// ~/Library/Application Support/<app>/ instead of ~/Library/Caches.
@(private="file")
APP_SUPPORT_CACHE_SUBDIRS := [?]string{
	"Cache",
	"Code Cache",
	"GPUCache",
}

app_cache_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	cat := types.category_of(.App_Cache)
	items := make([dynamic]types.CleanableItem, 0, 64, allocator)
	total: i64 = 0

	scan_app_support(&items, &total, allocator)
	scan_containers(&items, &total, allocator)
	scan_simple_children(&items, &total, "~/Library/WebKit", allocator)
	scan_simple_children(&items, &total, "~/Library/Saved Application State", allocator)

	return types.ScanResult{ category = cat, items = items[:], total_size = total }
}

app_cache_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.App_Cache), items, dry_run, allocator)
}

@(private="file")
scan_app_support :: proc(items: ^[dynamic]types.CleanableItem, total: ^i64, allocator: runtime.Allocator) {
	root := fsx.expand("~/Library/Application Support", context.temp_allocator)
	entries, err := os.read_directory_by_path(root, -1, context.temp_allocator)
	if err != nil {
		return
	}
	for app in entries {
		if app.type != .Directory {
			continue
		}
		for sub in APP_SUPPORT_CACHE_SUBDIRS {
			path := strings.concatenate({app.fullpath, "/", sub}, context.temp_allocator)
			append_dir_if_present(items, total, path, app.name, sub, allocator)
		}
		// Service Worker/CacheStorage is two levels deep.
		sw := strings.concatenate({app.fullpath, "/Service Worker/CacheStorage"}, context.temp_allocator)
		append_dir_if_present(items, total, sw, app.name, "Service Worker/CacheStorage", allocator)
	}
}

@(private="file")
scan_containers :: proc(items: ^[dynamic]types.CleanableItem, total: ^i64, allocator: runtime.Allocator) {
	root := fsx.expand("~/Library/Containers", context.temp_allocator)
	entries, err := os.read_directory_by_path(root, -1, context.temp_allocator)
	if err != nil {
		return
	}
	for container in entries {
		if container.type != .Directory {
			continue
		}
		cache_dir := strings.concatenate({container.fullpath, "/Data/Library/Caches"}, context.temp_allocator)
		fi, ferr := os.stat(cache_dir, context.temp_allocator)
		if ferr != nil || fi.type != .Directory {
			continue
		}
		children, cerr := os.read_directory_by_path(cache_dir, -1, context.temp_allocator)
		if cerr != nil {
			continue
		}
		for c in children {
			size := c.size
			if c.type == .Directory {
				size, _ = fsx.dir_size(c.fullpath)
			}
			if size <= 0 {
				continue
			}
			label := strings.concatenate({container.name, " · ", c.name}, allocator)
			append(items, types.CleanableItem{
				path              = strings.clone(c.fullpath, allocator),
				name              = label,
				size              = size,
				is_directory      = c.type == .Directory,
				modification_time = c.modification_time,
			})
			total^ += size
		}
	}
}

@(private="file")
scan_simple_children :: proc(items: ^[dynamic]types.CleanableItem, total: ^i64, raw_path: string, allocator: runtime.Allocator) {
	expanded := fsx.expand(raw_path, context.temp_allocator)
	entries, err := os.read_directory_by_path(expanded, -1, context.temp_allocator)
	if err != nil {
		return
	}
	for e in entries {
		size := e.size
		if e.type == .Directory {
			size, _ = fsx.dir_size(e.fullpath)
		}
		if size <= 0 {
			continue
		}
		append(items, types.CleanableItem{
			path              = strings.clone(e.fullpath, allocator),
			name              = strings.clone(e.name, allocator),
			size              = size,
			is_directory      = e.type == .Directory,
			modification_time = e.modification_time,
		})
		total^ += size
	}
}

@(private="file")
append_dir_if_present :: proc(items: ^[dynamic]types.CleanableItem, total: ^i64, path, app_name, sub_label: string, allocator: runtime.Allocator) {
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil || fi.type != .Directory {
		return
	}
	size, _ := fsx.dir_size(path)
	if size <= 0 {
		return
	}
	label := strings.concatenate({app_name, " · ", sub_label}, allocator)
	append(items, types.CleanableItem{
		path              = strings.clone(path, allocator),
		name              = label,
		size              = size,
		is_directory      = true,
		modification_time = fi.modification_time,
	})
	total^ += size
}
