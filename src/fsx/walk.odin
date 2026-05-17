package fsx

import "base:runtime"
import "core:os"
import "core:path/filepath"
import "core:time"

// WalkFilter controls which entries `walk_collect` keeps. All filters AND.
//   min_size:        drop files smaller than this many bytes (0 = no limit)
//   older_than_days: drop files modified within the last N days (0 = no limit)
//   max_depth:       stop descending past this depth (0 = unlimited)
//   include_dirs:    include directory entries themselves
//   follow_symlinks: stat through symlinks instead of lstat
WalkFilter :: struct {
	min_size:        i64,
	older_than_days: int,
	max_depth:       int,
	include_dirs:    bool,
	follow_symlinks: bool,
}

WalkEntry :: struct {
	path:              string,
	size:              i64,
	is_dir:            bool,
	modification_time: time.Time,
}

walk_collect :: proc(root: string, filter: WalkFilter, allocator := context.allocator) -> []WalkEntry {
	out := make([dynamic]WalkEntry, 0, 64, allocator)
	now := time.now()
	walk_recurse(&out, root, filter, 0, now, allocator)
	return out[:]
}

// dir_size sums the size of all regular files under `root`.
dir_size :: proc(root: string) -> (total_bytes: i64, file_count: int) {
	fi, err := os.stat(root, context.temp_allocator)
	if err != nil {
		return 0, 0
	}
	if fi.type == .Regular {
		return fi.size, 1
	}
	if fi.type != .Directory {
		return 0, 0
	}

	entries, derr := os.read_directory_by_path(root, -1, context.temp_allocator)
	if derr != nil {
		return 0, 0
	}
	for e in entries {
		#partial switch e.type {
		case .Regular:
			total_bytes += e.size
			file_count += 1
		case .Directory:
			sub, sub_count := dir_size(e.fullpath)
			total_bytes += sub
			file_count += sub_count
		}
	}
	return
}

@(private)
walk_recurse :: proc(
	out: ^[dynamic]WalkEntry,
	dir: string,
	filter: WalkFilter,
	depth: int,
	now: time.Time,
	allocator: runtime.Allocator,
) {
	if filter.max_depth > 0 && depth > filter.max_depth {
		return
	}

	entries, err := os.read_directory_by_path(dir, -1, context.temp_allocator)
	if err != nil {
		return
	}

	for e in entries {
		full_tmp, _ := filepath.join({dir, e.name}, context.temp_allocator)
		fi := e

		if filter.follow_symlinks && e.type == .Symlink {
			if r, rerr := os.stat(full_tmp, context.temp_allocator); rerr == nil {
				fi = r
			}
		}

		if fi.type == .Directory {
			if filter.include_dirs && passes_filter(fi, filter, now) {
				keep, _ := filepath.join({dir, e.name}, allocator)
				append(out, WalkEntry{
					path              = keep,
					size              = fi.size,
					is_dir            = true,
					modification_time = fi.modification_time,
				})
			}
			walk_recurse(out, full_tmp, filter, depth + 1, now, allocator)
		} else if fi.type == .Regular {
			if passes_filter(fi, filter, now) {
				keep, _ := filepath.join({dir, e.name}, allocator)
				append(out, WalkEntry{
					path              = keep,
					size              = fi.size,
					is_dir            = false,
					modification_time = fi.modification_time,
				})
			}
		}
	}
}

@(private)
passes_filter :: proc(fi: os.File_Info, filter: WalkFilter, now: time.Time) -> bool {
	if filter.min_size > 0 && fi.size < filter.min_size {
		return false
	}
	if filter.older_than_days > 0 {
		age := time.diff(fi.modification_time, now)
		threshold := time.Duration(filter.older_than_days) * 24 * time.Hour
		if age < threshold {
			return false
		}
	}
	return true
}
