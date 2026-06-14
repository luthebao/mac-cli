package clean_types

import "base:runtime"
import "core:time"

CategoryId :: enum {
	System_Cache,
	System_Logs,
	Temp_Files,
	Trash,
	Downloads,
	Browser_Cache,
	Dev_Cache,
	Homebrew,
	Docker,
	Ios_Backups,
	Mail_Attachments,
	Large_Files,
	Node_Modules,
	Duplicates,
	Launch_Agents,
	App_Cache,
	System_Cache_Root,
	Homebrew_Cleanup,
	Homebrew_Autoremove,
	Orphan_Symlinks,
}

Safety :: enum {
	Safe,
	Moderate,
	Risky,
}

Group :: enum {
	System_Junk,
	Development,
	Storage,
	Browsers,
	Large_Files,
}

Category :: struct {
	id:                      CategoryId,
	slug:                    string, // e.g. "system-cache" — stable identifier for config/UI
	name:                    string, // e.g. "User Cache Files" — display name
	group:                   Group,
	description:             string,
	safety:                  Safety,
	safety_note:             string, // empty if none
	supports_file_selection: bool,
}

CleanableItem :: struct {
	path:              string,
	size:              i64,
	name:              string,
	is_directory:      bool,
	modification_time: time.Time,
	// requires_sudo flags items that must be removed via `sudo rm -rf` because
	// the user lacks write permission (typical for /Library/Caches/* subdirs
	// owned by root or _spotlight). Scanner sets this; clean batches a single
	// sudo invocation per category to amortize the password prompt.
	requires_sudo:     bool,
}

ScanResult :: struct {
	category:   Category,
	items:      []CleanableItem,
	total_size: i64,
	error:      string, // empty = success
}

CleanResult :: struct {
	category:      Category,
	cleaned_items: int,
	freed_bytes:   i64,
	errors:        []string,
}

ScannerOptions :: struct {
	verbose:  bool,
	days_old: int,
	min_size: i64,
}

// Scanner is the contract every category implementation honors. Odin lacks
// interfaces — we model it as a struct of procs, one Scanner instance per
// category, registered in `catalog.odin`'s ALL_SCANNERS slice.
Scanner :: struct {
	category: Category,
	scan:     proc(opts: ScannerOptions, allocator: runtime.Allocator) -> ScanResult,
	clean:    proc(items: []CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> CleanResult,
}
