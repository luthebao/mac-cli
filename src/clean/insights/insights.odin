// Package clean_insights answers "where did my disk go?" — it ranks the
// largest directories and files under a path and surfaces "hidden space":
// caches, backups, and old downloads that quietly accumulate gigabytes.
//
// All measurement shells out through mc:sysx (du / find) per the project's
// subprocess discipline; nothing here touches core:os/exec directly.
package clean_insights

import "base:runtime"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

import "mc:fsx"
import "mc:sysx"

// Entry is one row in a size ranking — a top-level child directory or file,
// or (for the "largest files" list) an individual file found recursively.
Entry :: struct {
	name:   string,
	path:   string,
	size:   i64,
	is_dir: bool,
}

// Insight is a "hidden space" callout: a well-known path that tends to hoard
// disk space. `safe` marks paths that `mac-cli clean` can remove without data
// loss (pure caches) vs. ones holding real user data (backups, downloads).
Insight :: struct {
	name: string,
	path: string,
	size: i64,
	safe: bool,
}

Report :: struct {
	root:       string,
	total_size: i64,
	entries:    []Entry, // direct children, sorted largest-first
	largest:    []Entry, // largest individual files (recursive), largest-first
	insights:   []Insight,
}

// analyze builds the full report for `path`. top_files caps the "largest files"
// list. The caller owns everything via `allocator`.
analyze :: proc(path: string, top_files: int, allocator: runtime.Allocator) -> Report {
	expanded := fsx.expand(path, allocator)

	entries, total := du_tree(expanded, allocator)
	slice.sort_by(entries, proc(a, b: Entry) -> bool { return a.size > b.size })

	largest := largest_files(expanded, top_files, allocator)

	return Report{
		root       = expanded,
		total_size = total,
		entries    = entries,
		largest    = largest,
		insights   = hidden_space(allocator),
	}
}

// du_tree measures direct children + grand total. BSD du makes -a and -d
// mutually exclusive, so `du -k -d 1` reports subdirectory sizes (and the root
// total on its own line) but omits top-level *files* — we add those from a
// directory read. We parse stdout regardless of exit code: du returns non-zero
// when it hits an unreadable subdir but still prints what it could read.
@(private)
du_tree :: proc(root: string, allocator: runtime.Allocator) -> (entries: []Entry, total: i64) {
	r := sysx.run({"du", "-k", "-d", "1", root}, context.temp_allocator)
	out := make([dynamic]Entry, 0, 32, allocator)

	for line in strings.split_lines_iterator(&r.stdout) {
		tab := strings.index_byte(line, '\t')
		if tab < 0 {
			continue
		}
		kb, ok := strconv.parse_i64(strings.trim_space(line[:tab]))
		if !ok {
			continue
		}
		p := line[tab + 1:]
		size := kb * 1024

		if p == root {
			total = size // root's own line carries the grand total
			continue
		}
		name := p
		if i := strings.last_index(p, "/"); i >= 0 {
			name = p[i + 1:]
		}
		append(&out, Entry{
			name   = strings.clone(name, allocator),
			path   = strings.clone(p, allocator),
			size   = size,
			is_dir = true,
		})
	}

	// Top-level files (du -d 1 lists directories only; their bytes are already
	// in `total`, so we add the file entries without touching the total).
	if dirents, derr := os.read_directory_by_path(root, -1, context.temp_allocator); derr == nil {
		for e in dirents {
			if e.type == .Directory || e.size <= 0 {
				continue
			}
			append(&out, Entry{
				name   = strings.clone(e.name, allocator),
				path   = strings.clone(e.fullpath, allocator),
				size   = e.size,
				is_dir = false,
			})
		}
	}
	return out[:], total
}

// largest_files finds individual files ≥100 MB anywhere under root and returns
// the top N by size. find is metadata-only so this stays fast on large trees;
// we still cap how many paths we stat to keep pathological dirs bounded.
@(private)
largest_files :: proc(root: string, top_n: int, allocator: runtime.Allocator) -> []Entry {
	if top_n <= 0 {
		return nil
	}
	r := sysx.run({"find", root, "-type", "f", "-size", "+100000k"}, context.temp_allocator)

	// Bounded top-N insertion: `files` is kept sorted descending and capped at
	// top_n entries, so pathological result sets stay O(top_n) memory without
	// truncating by find's traversal order (a hard input cap could silently
	// drop the actual largest files in favor of smaller ones found earlier).
	files := make([dynamic]Entry, 0, top_n + 1, context.temp_allocator)
	for line in strings.split_lines_iterator(&r.stdout) {
		p := strings.trim_space(line)
		if p == "" {
			continue
		}
		fi, err := os.stat(p, context.temp_allocator)
		if err != nil {
			continue
		}
		if len(files) == top_n && fi.size <= files[len(files)-1].size {
			continue
		}
		ins := len(files)
		for existing, i in files {
			if fi.size > existing.size {
				ins = i
				break
			}
		}
		inject_at(&files, ins, Entry{name = fi.name, path = p, size = fi.size, is_dir = false})
		if len(files) > top_n {
			pop(&files)
		}
	}

	n := min(top_n, len(files))
	out := make([]Entry, n, allocator)
	for i in 0 ..< n {
		out[i] = Entry{
			name = strings.clone(files[i].name, allocator),
			path = strings.clone(files[i].path, allocator),
			size = files[i].size,
		}
	}
	return out
}

// CANDIDATE is a known hidden-space location. `safe` flags pure caches that
// `mac-cli clean` can wipe freely; backups/downloads hold real data so they're
// surfaced for *awareness*, not blind deletion.
@(private)
Candidate :: struct {
	name: string,
	rel:  string, // path relative to $HOME
	safe: bool,
}

@(private)
CANDIDATES := [?]Candidate{
	{"iOS Backups",       "Library/Application Support/MobileSync/Backup", false},
	{"System Logs",       "Library/Logs",                                  true},
	{"Homebrew Cache",    "Library/Caches/Homebrew",                       true},
	{"Xcode DerivedData", "Library/Developer/Xcode/DerivedData",           true},
	{"Xcode Simulators",  "Library/Developer/CoreSimulator/Devices",       false},
	{"Xcode Archives",    "Library/Developer/Xcode/Archives",              false},
	{"JetBrains Cache",   "Library/Caches/JetBrains",                      true},
	{"Spotify Cache",     "Library/Application Support/Spotify/PersistentCache", true},
	{"Docker Data",       "Library/Containers/com.docker.docker/Data",     false},
	{"pip Cache",         "Library/Caches/pip",                            true},
	{"Gradle Cache",      ".gradle/caches",                                true},
	{"CocoaPods Cache",   "Library/Caches/CocoaPods",                      true},
}

// hidden_space measures each known candidate that exists, plus the special-case
// "old Downloads" (files untouched for 90+ days). Returns entries sorted
// largest-first; zero-size / missing paths are dropped.
@(private)
hidden_space :: proc(allocator: runtime.Allocator) -> []Insight {
	home := fsx.home(context.temp_allocator)
	out := make([dynamic]Insight, 0, len(CANDIDATES) + 1, allocator)

	for c in CANDIDATES {
		full := strings.concatenate({home, "/", c.rel}, context.temp_allocator)
		if !os.exists(full) {
			continue
		}
		size := du_size(full)
		if size <= 0 {
			continue
		}
		append(&out, Insight{
			name = strings.clone(c.name, allocator),
			path = strings.clone(full, allocator),
			size = size,
			safe = c.safe,
		})
	}

	// Old Downloads — files in ~/Downloads not modified in 90+ days.
	downloads := strings.concatenate({home, "/Downloads"}, context.temp_allocator)
	if os.is_dir(downloads) {
		if size := old_downloads_size(downloads, 90); size > 0 {
			append(&out, Insight{
				name = strings.clone("Old Downloads (90d+)", allocator),
				path = strings.clone(downloads, allocator),
				size = size,
				safe = false,
			})
		}
	}

	slice.sort_by(out[:], proc(a, b: Insight) -> bool { return a.size > b.size })
	return out[:]
}

// du_size returns the recursive size of a path in bytes via `du -sk`, or 0.
@(private)
du_size :: proc(path: string) -> i64 {
	r := sysx.run_capture({"du", "-sk", path}, context.temp_allocator)
	tab := strings.index_byte(r.stdout, '\t')
	if tab < 0 {
		// fall back to whitespace split
		fields := strings.fields(r.stdout, context.temp_allocator)
		if len(fields) == 0 {
			return 0
		}
		kb, _ := strconv.parse_i64(fields[0])
		return kb * 1024
	}
	kb, _ := strconv.parse_i64(strings.trim_space(r.stdout[:tab]))
	return kb * 1024
}

// old_downloads_size sums the size of direct children of ~/Downloads whose
// modification time is older than `days`. Directories are sized via du.
@(private)
old_downloads_size :: proc(dir: string, days: int) -> i64 {
	entries, err := os.read_directory_by_path(dir, -1, context.temp_allocator)
	if err != nil {
		return 0
	}
	total: i64 = 0
	for e in entries {
		if strings.has_prefix(e.name, ".") {
			continue
		}
		age_days := time.duration_hours(time.since(e.modification_time)) / 24
		if age_days < f64(days) {
			continue
		}
		if e.type == .Directory {
			total += du_size(e.fullpath)
		} else {
			total += e.size
		}
	}
	return total
}
