package fsx

import "core:os"
import "core:path/filepath"
import "core:strings"

// SAFE_ROOTS lists path prefixes from which deletion is permitted.
// `{HOME}` is expanded to $HOME at runtime.
//
// CRITICAL — security-sensitive. Audit additions carefully:
//   - Adding `/` would allow rm -rf the whole machine.
//   - Adding `/Applications` would let bugs uninstall apps unintentionally.
//   - Adding paths users don't expect us to touch breaks our safety promise.
SAFE_ROOTS := [?]string{
	"{HOME}/.Trash",
	"{HOME}/Downloads",
	"{HOME}/Library/Caches",
	"{HOME}/Library/Logs",
	"{HOME}/Library/Application Support/MobileSync/Backup",
	"{HOME}/Library/Mail/Downloads",
	"{HOME}/Library/Mail/V10",
	"{HOME}/Library/Developer/Xcode/DerivedData",
	"{HOME}/Library/Developer/Xcode/Archives",
	"{HOME}/Library/Developer/CoreSimulator/Caches",
	"{HOME}/Library/Developer/CoreSimulator/Devices",
	"{HOME}/Library/LaunchAgents",
	"{HOME}/.npm",
	"{HOME}/.yarn",
	"{HOME}/.pnpm-store",
	"{HOME}/.cache",
	"{HOME}/.cargo/registry",
	"{HOME}/.gradle/caches",
	"{HOME}/.mac-cli",
	"/tmp",
	"/private/tmp",
	"/private/var/folders",
	"/var/folders",
	"/Library/Caches",
	"/Library/Logs",
	"/Library/LaunchAgents",
}

// DANGER_PATHS always refuse — even if technically below a SAFE_ROOT.
// Catches symlink escapes and weird edge cases.
DANGER_PATHS := [?]string{
	"/", "/System", "/usr", "/bin", "/sbin", "/etc", "/var",
	"/Library/Frameworks", "/Library/Extensions",
	"/Applications", "/Network", "/Volumes",
}

DeleteError :: enum {
	None,
	Path_Not_Safe,
	Path_Not_Found,
	System_Error,
}

// is_path_safe returns true iff `path` is strictly under one of SAFE_ROOTS
// and not equal to or under any DANGER_PATHS. Symlinks must be resolved by
// the caller — we treat the input path as already canonical.
is_path_safe :: proc(path: string) -> bool {
	if len(path) == 0 || path[0] != '/' {
		return false // require absolute paths
	}

	cleaned, _ := filepath.clean(path, context.temp_allocator)

	for danger in DANGER_PATHS {
		if cleaned == danger {
			return false
		}
		// Refuse anything strictly under a danger path too.
		if has_path_prefix(cleaned, danger) {
			return false
		}
	}

	h := home(context.temp_allocator)
	for root in SAFE_ROOTS {
		expanded := root
		if strings.contains(root, "{HOME}") {
			if h == "" {
				continue
			}
			expanded, _ = strings.replace_all(root, "{HOME}", h, context.temp_allocator)
		}
		// Refuse deleting the safe root itself; require something strictly inside.
		if cleaned == expanded {
			return false
		}
		if has_path_prefix(cleaned, expanded) {
			return true
		}
	}
	return false
}

// has_path_prefix returns true if `path` is strictly inside `prefix`,
// i.e. `prefix/something`. `prefix` itself is NOT considered "under" itself.
has_path_prefix :: proc(path, prefix: string) -> bool {
	if !strings.has_prefix(path, prefix) {
		return false
	}
	if len(path) == len(prefix) {
		return false // exactly equal
	}
	// Require the next char to be the path separator — guards against
	// e.g. "/tmpfoo" matching "/tmp".
	return path[len(prefix)] == '/'
}

// safe_delete removes `path` if it passes is_path_safe. Returns bytes freed.
safe_delete :: proc(path: string) -> (freed_bytes: i64, err: DeleteError) {
	if !is_path_safe(path) {
		return 0, .Path_Not_Safe
	}

	fi, serr := os.lstat(path, context.temp_allocator)
	if serr != nil {
		if ge, ok := serr.(os.General_Error); ok && ge == .Not_Exist {
			return 0, .Path_Not_Found
		}
		return 0, .System_Error
	}

	size: i64 = 0
	if fi.type == .Directory {
		size, _ = dir_size(path)
		if rerr := os.remove_all(path); rerr != nil {
			return 0, .System_Error
		}
	} else {
		size = fi.size
		if rerr := os.remove(path); rerr != nil {
			return 0, .System_Error
		}
	}
	return size, .None
}
