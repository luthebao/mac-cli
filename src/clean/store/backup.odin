package clean_store

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "mc:fsx"

// BACKUP_MAX_BYTES is the size cap above which items are deleted without
// being backed up first — copying multi-GB caches would just amplify the
// I/O cost without giving meaningful safety net.
BACKUP_MAX_BYTES :: 50 * 1024 * 1024 // 50 MB

// BACKUP_TTL_DAYS controls how long backups are retained by `backup --clean`.
BACKUP_TTL_DAYS :: 7

backup_root :: proc(allocator := context.allocator) -> string {
	return fsx.join_home(".mac-cli", "clean", "backups", allocator = allocator)
}

// session_dir returns a freshly-allocated path for the current backup batch,
// suffixed with a timestamp like "2026-05-17T16-30-00Z".
session_dir :: proc(allocator := context.allocator) -> string {
	now := time.now()
	y, m, d := time.date(now)
	hour, min, sec := time.clock(now)
	stamp := fmt.aprintf("%04d-%02d-%02dT%02d-%02d-%02dZ", y, int(m), d, hour, min, sec, allocator = context.temp_allocator)
	root := backup_root(context.temp_allocator)
	joined, _ := filepath.join({root, stamp}, allocator)
	return joined
}

// BackupEntry describes one on-disk backup, used by `backup --list`.
BackupEntry :: struct {
	path:           string,
	created_at:     time.Time,
	size:           i64,
}

// list_backups enumerates session directories under backup_root().
// Returned slice is owned by the caller; entries reference temp_allocator
// strings so callers should clone if needed.
list_backups :: proc(allocator := context.allocator) -> []BackupEntry {
	root := backup_root(context.temp_allocator)
	entries, err := os.read_directory_by_path(root, -1, context.temp_allocator)
	if err != nil {
		return {}
	}

	out := make([dynamic]BackupEntry, 0, len(entries), allocator)
	for e in entries {
		if e.type != .Directory {
			continue
		}
		size, _ := fsx.dir_size(e.fullpath)
		append(&out, BackupEntry{
			path       = strings.clone(e.fullpath, allocator),
			created_at = e.modification_time,
			size       = size,
		})
	}
	return out[:]
}

// clean_old_backups removes session directories whose mtime is older than
// BACKUP_TTL_DAYS. Returns the count deleted.
clean_old_backups :: proc() -> int {
	root := backup_root(context.temp_allocator)
	entries, err := os.read_directory_by_path(root, -1, context.temp_allocator)
	if err != nil {
		return 0
	}

	now := time.now()
	threshold := time.Duration(BACKUP_TTL_DAYS) * 24 * time.Hour
	count := 0
	for e in entries {
		if e.type != .Directory {
			continue
		}
		age := time.diff(e.modification_time, now)
		if age < threshold {
			continue
		}
		if _, derr := fsx.safe_delete(e.fullpath); derr == .None {
			count += 1
		}
	}
	return count
}

// backup_should_skip returns true iff an item is too large to be worth
// copying into the backup directory.
backup_should_skip :: proc(size: i64) -> bool {
	return size > BACKUP_MAX_BYTES
}
