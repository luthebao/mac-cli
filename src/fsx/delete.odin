package fsx

import "core:os"
import "core:path/filepath"
import "core:strings"

// SAFE_ROOTS lists path prefixes from which deletion is permitted.
// `{HOME}` is expanded to $HOME at runtime. A `*` segment matches exactly
// one path component (no slashes inside), enabling patterns like
// `~/Library/Application Support/*/Cache` without authorizing the whole
// Application Support tree.
//
// CRITICAL — security-sensitive. Audit additions carefully:
//   - Adding `/` would allow rm -rf the whole machine.
//   - Adding `/Applications` would let bugs uninstall apps unintentionally.
//   - Adding paths users don't expect us to touch breaks our safety promise.
//   - Wildcard `*` is one segment. `**` is NOT supported.
SAFE_ROOTS := [?]string{
	"{HOME}/.Trash",
	"{HOME}/Downloads",
	"{HOME}/Library/Caches",
	"{HOME}/Library/Logs",
	"{HOME}/Library/Application Support/MobileSync/Backup",
	"{HOME}/Library/Application Support/*/Cache",
	"{HOME}/Library/Application Support/*/Code Cache",
	"{HOME}/Library/Application Support/*/GPUCache",
	"{HOME}/Library/Application Support/*/Service Worker/CacheStorage",
	"{HOME}/Library/Containers/*/Data/Library/Caches",
	"{HOME}/Library/WebKit",
	"{HOME}/Library/Saved Application State",
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
	"{HOME}/.local/bin",
	"{HOME}/bin",
	"/opt/homebrew/bin",
	"/tmp",
	"/private/tmp",
	"/private/var/folders",
	"/var/folders",
	"/Library/Caches",
	"/Library/Logs",
	"/Library/LaunchAgents",
	"/Volumes/*/.Trashes",
}

// DANGER_PATHS always refuse — even if technically below a SAFE_ROOT.
// Catches symlink escapes and weird edge cases.
//
// /Volumes is intentionally NOT here: external-trash deletion needs to reach
// /Volumes/<disk>/.Trashes/<uid>, and that path is gated narrowly by the
// SAFE_ROOTS wildcard above. Anything outside that wildcard on a volume
// still won't match any safe root and will be refused.
DANGER_PATHS := [?]string{
	"/", "/System", "/usr", "/bin", "/sbin", "/etc", "/var",
	"/Library/Frameworks", "/Library/Extensions",
	"/Applications", "/Network",
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
		if strings.contains(expanded, "*") {
			if matches_wildcard_root(cleaned, expanded) {
				return true
			}
			continue
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

// matches_wildcard_root returns true iff `path` is strictly under `pattern`,
// where `*` in pattern matches exactly one path segment. A trailing match
// requires the path to have MORE segments than the pattern — the pattern
// itself is treated as the safe-root boundary and refused on equality.
matches_wildcard_root :: proc(path, pattern: string) -> bool {
	path_segs := strings.split(path, "/", context.temp_allocator)
	pat_segs  := strings.split(pattern, "/", context.temp_allocator)
	if len(path_segs) <= len(pat_segs) {
		return false
	}
	for seg, i in pat_segs {
		if seg == "*" {
			// A wildcard segment must consume something non-empty.
			if path_segs[i] == "" {
				return false
			}
			continue
		}
		if path_segs[i] != seg {
			return false
		}
	}
	return true
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
