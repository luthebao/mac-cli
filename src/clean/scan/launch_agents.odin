package clean_scan

import "base:runtime"
import "core:os"
import "core:strings"

import "mc:clean/types"

// Orphaned launch agents are .plist files referencing a Program path that
// no longer exists. We parse the plist's first <string>...</string> after
// a <key>Program</key> or <key>ProgramArguments</key> — adequate for the
// common cases without pulling in a full plist parser.
launch_agents_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	cat := types.category_of(.Launch_Agents)
	items := make([dynamic]types.CleanableItem, 0, 8, allocator)
	total: i64 = 0

	roots := []string{
		expand_user("~/Library/LaunchAgents"),
		"/Library/LaunchAgents",
	}
	for root in roots {
		entries, err := os.read_directory_by_path(root, -1, context.temp_allocator)
		if err != nil {
			continue
		}
		for e in entries {
			if e.type != .Regular || !strings.has_suffix(e.name, ".plist") {
				continue
			}
			target := extract_plist_target(e.fullpath)
			if target == "" {
				continue
			}
			if _, terr := os.stat(target, context.temp_allocator); terr == nil {
				continue // target exists — not orphaned
			}
			append(&items, types.CleanableItem{
				path              = strings.clone(e.fullpath, allocator),
				name              = strings.clone(e.name, allocator),
				size              = e.size,
				is_directory      = false,
				modification_time = e.modification_time,
				// /Library/LaunchAgents is root-owned; deleting there needs
				// the batched sudo path, same as system_cache_root.
				requires_sudo     = root == "/Library/LaunchAgents",
			})
			total += e.size
		}
	}

	return types.ScanResult{
		category   = cat,
		items      = items[:],
		total_size = total,
	}
}

launch_agents_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	return clean_items(types.category_of(.Launch_Agents), items, dry_run, allocator)
}

@(private)
extract_plist_target :: proc(path: string) -> string {
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil {
		return ""
	}
	content := string(data)

	// Look for <key>Program</key> followed by <string>PATH</string>
	if t := pull_after(content, "<key>Program</key>"); t != "" {
		return t
	}
	if t := pull_after(content, "<key>ProgramArguments</key>"); t != "" {
		return t
	}
	return ""
}

@(private)
pull_after :: proc(content, marker: string) -> string {
	idx := strings.index(content, marker)
	if idx < 0 {
		return ""
	}
	tail := content[idx + len(marker):]
	open := strings.index(tail, "<string>")
	if open < 0 {
		return ""
	}
	body := tail[open + len("<string>"):]
	close := strings.index(body, "</string>")
	if close < 0 {
		return ""
	}
	return strings.trim_space(body[:close])
}

@(private)
expand_user :: proc(path: string) -> string {
	// Lazy local copy to avoid taking a dependency on fsx just for this.
	if !strings.has_prefix(path, "~/") {
		return path
	}
	home := os.get_env("HOME", context.temp_allocator)
	if home == "" {
		return path
	}
	return strings.concatenate({home, path[1:]}, context.temp_allocator)
}
