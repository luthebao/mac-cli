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
	"{HOME}/.bundle/cache",
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

// SAFE_LEAF_ROOTS are the subset of SAFE_ROOTS that may be deleted *wholesale*
// (the directory itself, not only things strictly inside it). These are pure,
// fully regenerable caches that scanners surface as a single rolled-up item
// whose path equals the root — so the usual "refuse the root itself" guard
// would otherwise (wrongly) block the very cleanup we intend.
//
// Membership is compared against the SAFE_ROOTS *template* string (with the
// {HOME} placeholder), so entries here must match a SAFE_ROOTS entry verbatim.
//
// CRITICAL: only list directories whose ENTIRE contents are disposable. Broad
// containers that also hold user data (Downloads, Library/Caches, .Trash,
// Logs, .cargo as a whole) must NEVER appear here — for those we only ever
// delete strictly-inside paths.
SAFE_LEAF_ROOTS := [?]string{
	"{HOME}/Library/Developer/Xcode/DerivedData",
	"{HOME}/Library/Developer/Xcode/Archives",
	"{HOME}/Library/Developer/CoreSimulator/Caches",
	"{HOME}/.cargo/registry",
	"{HOME}/.pnpm-store",
	"{HOME}/.gradle/caches",
	"{HOME}/.bundle/cache",
	// Wildcard leaf caches: the App Caches scanner surfaces these cache dirs
	// themselves (e.g. ~/.../discord/Cache), which equals the pattern — so they
	// must be deletable wholesale, not just contents-only.
	"{HOME}/Library/Application Support/*/Cache",
	"{HOME}/Library/Application Support/*/Code Cache",
	"{HOME}/Library/Application Support/*/GPUCache",
	"{HOME}/Library/Application Support/*/Service Worker/CacheStorage",
	"{HOME}/Library/Containers/*/Data/Library/Caches",
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
			// Leaf wildcard caches may be deleted as the matched dir itself
			// (exact segment count); others require something strictly inside.
			if matches_wildcard_root(cleaned, expanded, is_leaf_root(root)) {
				return true
			}
			continue
		}
		if cleaned == expanded {
			// Most safe roots are broad containers we only delete *inside* of,
			// so equality is refused. A few (SAFE_LEAF_ROOTS) are pure caches a
			// scanner surfaces as one rolled-up item — those may be removed
			// wholesale.
			return is_leaf_root(root)
		}
		if has_path_prefix(cleaned, expanded) {
			return true
		}
	}
	return false
}

// is_leaf_root reports whether a SAFE_ROOTS template entry is also flagged as
// wholesale-deletable in SAFE_LEAF_ROOTS. Compares templates (with {HOME}), so
// no expansion is needed.
@(private)
is_leaf_root :: proc(root_template: string) -> bool {
	for lr in SAFE_LEAF_ROOTS {
		if lr == root_template {
			return true
		}
	}
	return false
}

// matches_wildcard_root returns true iff `path` is under `pattern`, where `*`
// in pattern matches exactly one path segment. By default the path must have
// MORE segments than the pattern (strictly inside) — the pattern itself is the
// safe-root boundary and refused on equality. When `allow_equal` is set (leaf
// caches), the matched directory itself is also accepted.
matches_wildcard_root :: proc(path, pattern: string, allow_equal := false) -> bool {
	path_segs := strings.split(path, "/", context.temp_allocator)
	pat_segs  := strings.split(pattern, "/", context.temp_allocator)
	if allow_equal {
		if len(path_segs) < len(pat_segs) {
			return false
		}
	} else if len(path_segs) <= len(pat_segs) {
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

// is_path_safe_reviewed is the relaxed gate for files the user has explicitly
// reviewed and hand-picked — the file-selection categories (Large Files,
// Duplicate Files, old Downloads), which surface arbitrary files from anywhere
// under $HOME rather than from a known cache location.
//
// The strict is_path_safe allowlist exists to stop *accidental/automated*
// deletion of unexpected paths. Per-file user selection is a different trust
// model: anything the user deliberately ticked may go, provided it's (a) an
// absolute path, (b) strictly inside their home directory, and (c) not a
// protected system location. (a)+(c) are defense-in-depth; the scanners that
// feed this only ever produce paths under $HOME.
is_path_safe_reviewed :: proc(path: string) -> bool {
	if len(path) == 0 || path[0] != '/' {
		return false
	}
	cleaned, _ := filepath.clean(path, context.temp_allocator)

	for danger in DANGER_PATHS {
		if cleaned == danger || has_path_prefix(cleaned, danger) {
			return false
		}
	}

	h := home(context.temp_allocator)
	if h == "" {
		return false
	}
	// Strictly inside $HOME — never $HOME itself, never outside it.
	return has_path_prefix(cleaned, h)
}

// safe_delete removes `path` if it passes is_path_safe. When `reviewed` is set
// (a user-selected file from a review-each category) it additionally accepts
// paths cleared by is_path_safe_reviewed. Returns bytes freed.
safe_delete :: proc(path: string, reviewed := false) -> (freed_bytes: i64, err: DeleteError) {
	allowed := is_path_safe(path)
	if !allowed && reviewed {
		allowed = is_path_safe_reviewed(path)
	}
	if !allowed {
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
