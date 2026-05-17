package clean_store

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"

import "mc:fsx"

// Config holds user-tunable settings, persisted at ~/.mac-cli/clean/config.json.
// Add fields here; JSON tags are derived from field names by default.
Config :: struct {
	file_picker:        bool, // force file picker for ALL categories
	include_risky:      bool, // include risky categories by default
	absolute_paths:     bool, // show absolute paths instead of abbreviated
	disable_backups:    bool, // skip the pre-delete backup step
	min_duplicate_size: i64,  // skip duplicate detection on files smaller than this
	downloads_days:     int,  // age threshold for `downloads` scanner
}

DEFAULT_CONFIG :: Config{
	file_picker        = false,
	include_risky      = false,
	absolute_paths     = false,
	disable_backups    = false,
	min_duplicate_size = 1024 * 1024, // 1 MB
	downloads_days     = 30,
}

// config_path returns ~/.mac-cli/clean/config.json (absolute).
config_path :: proc(allocator := context.allocator) -> string {
	return fsx.join_home(".mac-cli", "clean", "config.json", allocator = allocator)
}

config_dir :: proc(allocator := context.allocator) -> string {
	return fsx.join_home(".mac-cli", "clean", allocator = allocator)
}

config_exists :: proc() -> bool {
	p := config_path(context.temp_allocator)
	_, err := os.stat(p, context.temp_allocator)
	return err == nil
}

// load_config reads the on-disk config. Falls back to DEFAULT_CONFIG on any
// error (missing file, parse failure, etc.) so the cleaner always has a
// usable config without crashing.
load_config :: proc() -> Config {
	p := config_path(context.temp_allocator)
	data, err := os.read_entire_file_from_path(p, context.temp_allocator)
	if err != nil {
		return DEFAULT_CONFIG
	}
	cfg := DEFAULT_CONFIG
	if jerr := json.unmarshal(data, &cfg); jerr != nil {
		return DEFAULT_CONFIG
	}
	return cfg
}

// init_config creates the directory and writes the default config if absent.
// Returns the absolute path and any error encountered.
init_config :: proc() -> (path: string, err: string) {
	dir := config_dir(context.temp_allocator)
	if derr := os.make_directory_all(dir); derr != nil {
		return "", fmt.aprintf("failed to create %s: %v", dir, derr, allocator = context.allocator)
	}

	p := config_path(context.allocator)
	data, jerr := json.marshal(DEFAULT_CONFIG, {pretty = true, use_spaces = false}, context.temp_allocator)
	if jerr != nil {
		return p, fmt.aprintf("failed to encode default config: %v", jerr, allocator = context.allocator)
	}

	if werr := os.write_entire_file_from_bytes(p, data); werr != nil {
		return p, fmt.aprintf("failed to write %s: %v", p, werr, allocator = context.allocator)
	}
	return p, ""
}

// save_config writes the given config to disk, creating parents as needed.
save_config :: proc(cfg: Config) -> string {
	dir := config_dir(context.temp_allocator)
	if derr := os.make_directory_all(dir); derr != nil {
		return fmt.aprintf("failed to create %s: %v", dir, derr, allocator = context.allocator)
	}

	data, jerr := json.marshal(cfg, {pretty = true, use_spaces = false}, context.temp_allocator)
	if jerr != nil {
		return fmt.aprintf("failed to encode config: %v", jerr, allocator = context.allocator)
	}

	p := config_path(context.temp_allocator)
	if werr := os.write_entire_file_from_bytes(p, data); werr != nil {
		return fmt.aprintf("failed to write %s: %v", p, werr, allocator = context.allocator)
	}
	_ = filepath.dir // keep filepath import used for future extensions
	return ""
}
