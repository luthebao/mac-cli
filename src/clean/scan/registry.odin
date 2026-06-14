package clean_scan

import "mc:clean/types"

// We can't initialize ALL_SCANNERS at global scope because Odin disallows
// procedure calls that require an implicit `context` at module init. So we
// build the table lazily on first access and cache it.
@(private="file") g_all_scanners: [20]types.Scanner
@(private="file") g_inited: bool

all_scanners :: proc() -> []types.Scanner {
	if !g_inited {
		g_all_scanners[0]  = {category = types.category_of(.Trash),               scan = trash_scan,               clean = trash_clean}
		g_all_scanners[1]  = {category = types.category_of(.Temp_Files),          scan = temp_files_scan,          clean = temp_files_clean}
		g_all_scanners[2]  = {category = types.category_of(.Browser_Cache),       scan = browser_cache_scan,       clean = browser_cache_clean}
		g_all_scanners[3]  = {category = types.category_of(.Homebrew),            scan = homebrew_scan,            clean = homebrew_clean}
		g_all_scanners[4]  = {category = types.category_of(.Docker),              scan = docker_scan,              clean = docker_clean}
		g_all_scanners[5]  = {category = types.category_of(.System_Cache),        scan = system_cache_scan,        clean = system_cache_clean}
		g_all_scanners[6]  = {category = types.category_of(.System_Logs),         scan = system_logs_scan,         clean = system_logs_clean}
		g_all_scanners[7]  = {category = types.category_of(.Dev_Cache),           scan = dev_cache_scan,           clean = dev_cache_clean}
		g_all_scanners[8]  = {category = types.category_of(.Node_Modules),        scan = node_modules_scan,        clean = node_modules_clean}
		g_all_scanners[9]  = {category = types.category_of(.Launch_Agents),       scan = launch_agents_scan,       clean = launch_agents_clean}
		g_all_scanners[10] = {category = types.category_of(.Downloads),           scan = downloads_scan,           clean = downloads_clean}
		g_all_scanners[11] = {category = types.category_of(.Ios_Backups),         scan = ios_backups_scan,         clean = ios_backups_clean}
		g_all_scanners[12] = {category = types.category_of(.Mail_Attachments),    scan = mail_attachments_scan,    clean = mail_attachments_clean}
		g_all_scanners[13] = {category = types.category_of(.Large_Files),         scan = large_files_scan,         clean = large_files_clean}
		g_all_scanners[14] = {category = types.category_of(.Duplicates),          scan = duplicates_scan,          clean = duplicates_clean}
		g_all_scanners[15] = {category = types.category_of(.App_Cache),           scan = app_cache_scan,           clean = app_cache_clean}
		g_all_scanners[16] = {category = types.category_of(.System_Cache_Root),   scan = system_cache_root_scan,   clean = system_cache_root_clean}
		g_all_scanners[17] = {category = types.category_of(.Homebrew_Cleanup),    scan = homebrew_cleanup_scan,    clean = homebrew_cleanup_clean}
		g_all_scanners[18] = {category = types.category_of(.Homebrew_Autoremove), scan = homebrew_autoremove_scan, clean = homebrew_autoremove_clean}
		g_all_scanners[19] = {category = types.category_of(.Orphan_Symlinks),     scan = orphan_symlinks_scan,     clean = orphan_symlinks_clean}
		g_inited = true
	}
	return g_all_scanners[:]
}

scanners_for :: proc(include_risky: bool, allocator := context.allocator) -> []types.Scanner {
	out := make([dynamic]types.Scanner, 0, 16, allocator)
	for s in all_scanners() {
		if s.category.safety == .Risky && !include_risky {
			continue
		}
		append(&out, s)
	}
	return out[:]
}
