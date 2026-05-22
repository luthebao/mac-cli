package clean_scan

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"

import "mc:clean/store"
import "mc:clean/types"
import "mc:fsx"
import "mc:sysx"

// PathSpec describes one entry to scan: either a directory whose contents
// are individually surfaced (children=true) or a leaf the caller wants
// reported as a single rolled-up item.
PathSpec :: struct {
	path:     string, // raw, may contain "~"
	children: bool,   // if true, list each direct child as its own item
}

// scan_paths is the workhorse for path-list-style scanners.
// Behavior:
//   - For each spec, expand `~` to $HOME.
//   - If the path doesn't exist or isn't readable, skip silently.
//   - If `children`, enumerate direct children and report each as an item.
//   - If !children, report the path itself as a single item with its
//     recursive directory size.
scan_paths :: proc(
	cat: types.Category,
	specs: []PathSpec,
	allocator: runtime.Allocator,
) -> types.ScanResult {
	items := make([dynamic]types.CleanableItem, 0, 32, allocator)
	total: i64 = 0
	denied: int = 0

	for spec in specs {
		expanded := fsx.expand(spec.path, context.temp_allocator)
		fi, err := os.stat(expanded, context.temp_allocator)
		if err != nil {
			continue
		}

		if spec.children && fi.type == .Directory {
			entries, derr := os.read_directory_by_path(expanded, -1, context.temp_allocator)
			if derr != nil {
				// TCC ("Files and Folders" / Full Disk Access) commonly blocks
				// reads of ~/.Trash, ~/Library/Mail, ~/Library/Safari, etc.
				// We can stat the dir (metadata is allowed) but enumerating
				// contents returns Permission_Denied. Track it so the caller
				// can surface a helpful hint rather than silently report 0.
				if is_permission_error(derr) {
					denied += 1
				}
				continue
			}
			for e in entries {
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
		} else {
			size := fi.size
			if fi.type == .Directory {
				size, _ = fsx.dir_size(expanded)
			}
			if size <= 0 {
				continue
			}
			append(&items, types.CleanableItem{
				path              = strings.clone(expanded, allocator),
				name              = strings.clone(fi.name, allocator),
				size              = size,
				is_directory      = fi.type == .Directory,
				modification_time = fi.modification_time,
			})
			total += size
		}
	}

	res := types.ScanResult{
		category   = cat,
		items      = items[:],
		total_size = total,
	}
	if len(items) == 0 && denied > 0 {
		res.error = strings.clone("permission denied — grant Full Disk Access to this terminal", allocator)
	}
	return res
}

// is_permission_error checks if an os error represents permission denial.
// On POSIX, EPERM and EACCES are normalized into io.Error.Permission_Denied
// by Odin's stdlib — see core/os/errors_posix.odin.
@(private)
is_permission_error :: proc(err: os.Error) -> bool {
	if ie, ok := err.(io.Error); ok {
		return ie == .Permission_Denied
	}
	return false
}

// clean_items deletes each item via fsx.safe_delete, optionally backing up
// small items first (controlled by clean/store/BACKUP_MAX_BYTES).
// dry_run=true reports what WOULD be cleaned without changing anything.
//
// Items flagged `requires_sudo` are collected and removed in a single
// `sudo /bin/rm -rf …` invocation at the end, so the user sees at most one
// password prompt per category.
clean_items :: proc(
	cat: types.Category,
	items: []types.CleanableItem,
	dry_run: bool,
	allocator: runtime.Allocator,
) -> types.CleanResult {
	res := types.CleanResult{ category = cat }
	errors := make([dynamic]string, 0, 0, allocator)
	sudo_paths := make([dynamic]string, 0, 0, context.temp_allocator)
	sudo_freed: i64 = 0
	sudo_count: int = 0

	for item in items {
		if dry_run {
			res.cleaned_items += 1
			res.freed_bytes += item.size
			continue
		}

		if item.requires_sudo {
			// Validate now so a buggy scanner can't sneak unsafe paths into
			// the sudo batch.
			if !fsx.is_path_safe(item.path) {
				append(&errors, strings.concatenate({"refused (path not safe): ", item.path}, allocator))
				continue
			}
			append(&sudo_paths, item.path)
			sudo_freed += item.size
			sudo_count += 1
			continue
		}

		// Backup tier: small items get copied; large ones are direct-deleted.
		// (Phase 6 wires actual file copy; phase 4 only stages the path.)
		_ = store.backup_should_skip(item.size)

		freed, derr := fsx.safe_delete(item.path)
		switch derr {
		case .None:
			res.cleaned_items += 1
			res.freed_bytes += freed
		case .Path_Not_Safe:
			append(&errors, strings.concatenate({"refused (path not safe): ", item.path}, allocator))
		case .Path_Not_Found:
			// Silently skip — race with another delete is fine.
		case .System_Error:
			append(&errors, strings.concatenate({"system error: ", item.path}, allocator))
		}
	}

	if !dry_run && len(sudo_paths) > 0 {
		argv := make([dynamic]string, 0, len(sudo_paths) + 3, context.temp_allocator)
		append(&argv, "/usr/bin/sudo", "/bin/rm", "-rf")
		for p in sudo_paths {
			append(&argv, p)
		}
		if sysx.run_quiet(argv[:]) {
			res.cleaned_items += sudo_count
			res.freed_bytes += sudo_freed
		} else {
			msg := fmt.aprintf("sudo deletion failed for %d item(s)", sudo_count, allocator = allocator)
			append(&errors, msg)
		}
	}

	res.errors = errors[:]
	return res
}
