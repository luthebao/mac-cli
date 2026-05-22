package clean_scan

import "base:runtime"
import "core:strconv"
import "core:strings"

import "mc:clean/types"
import "mc:sysx"

// homebrew_cleanup_scan wraps `brew cleanup -n --prune=all`. The total size is
// parsed from the trailing "This operation would free approximately X" line
// brew prints. Returned as a single CleanableItem; deletion re-runs brew
// cleanup without --dry-run.
homebrew_cleanup_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	cat := types.category_of(.Homebrew_Cleanup)
	brew := find_brew()
	if brew == "" {
		return types.ScanResult{ category = cat }
	}

	out := sysx.run_capture({brew, "cleanup", "-n", "--prune=all"}, context.temp_allocator)
	if !out.ok {
		return types.ScanResult{ category = cat }
	}
	size := parse_brew_cleanup_size(out.stdout)
	if size <= 0 {
		return types.ScanResult{ category = cat }
	}

	items := make([]types.CleanableItem, 1, allocator)
	items[0] = types.CleanableItem{
		path = strings.clone(brew, allocator),
		name = strings.clone("brew cleanup --prune=all", allocator),
		size = size,
	}
	return types.ScanResult{ category = cat, items = items, total_size = size }
}

homebrew_cleanup_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	cat := types.category_of(.Homebrew_Cleanup)
	res := types.CleanResult{ category = cat }
	if dry_run {
		for it in items {
			res.cleaned_items += 1
			res.freed_bytes += it.size
		}
		return res
	}
	brew := find_brew()
	if brew == "" {
		return res
	}
	for it in items {
		if sysx.run_quiet({brew, "cleanup", "--prune=all"}) {
			res.cleaned_items += 1
			res.freed_bytes += it.size
		}
		break // single action covers all; no per-item loop needed
	}
	return res
}

// homebrew_autoremove_scan wraps `brew autoremove --dry-run`. Brew doesn't
// report disk size for autoremove (would require per-pkg `brew info` calls),
// so size is 0 and we surface the package list in the item name instead.
homebrew_autoremove_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	cat := types.category_of(.Homebrew_Autoremove)
	brew := find_brew()
	if brew == "" {
		return types.ScanResult{ category = cat }
	}
	out := sysx.run_capture({brew, "autoremove", "--dry-run"}, context.temp_allocator)
	if !out.ok {
		return types.ScanResult{ category = cat }
	}
	pkgs := parse_brew_autoremove_packages(out.stdout, context.temp_allocator)
	if len(pkgs) == 0 {
		return types.ScanResult{ category = cat }
	}

	joined := strings.join(pkgs, ", ", context.temp_allocator)
	label := strings.concatenate({"autoremove: ", joined}, allocator)
	items := make([]types.CleanableItem, 1, allocator)
	items[0] = types.CleanableItem{
		path = strings.clone(brew, allocator),
		name = label,
		size = 0,
	}
	return types.ScanResult{ category = cat, items = items }
}

homebrew_autoremove_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	cat := types.category_of(.Homebrew_Autoremove)
	res := types.CleanResult{ category = cat }
	if dry_run {
		for it in items {
			res.cleaned_items += 1
			res.freed_bytes += it.size
		}
		return res
	}
	brew := find_brew()
	if brew == "" {
		return res
	}
	for it in items {
		if sysx.run_quiet({brew, "autoremove"}) {
			res.cleaned_items += 1
			res.freed_bytes += it.size
		}
		break
	}
	return res
}

@(private="file")
find_brew :: proc() -> string {
	r := sysx.run_capture({"/opt/homebrew/bin/brew", "--version"}, context.temp_allocator)
	if r.ok {
		return "/opt/homebrew/bin/brew"
	}
	r = sysx.run_capture({"/usr/local/bin/brew", "--version"}, context.temp_allocator)
	if r.ok {
		return "/usr/local/bin/brew"
	}
	return ""
}

// parse_brew_cleanup_size extracts the trailing
//   "==> This operation would free approximately X.XGB of disk space."
// line. Returns bytes, 0 if not found.
@(private)
parse_brew_cleanup_size :: proc(stdout: string) -> i64 {
	needle := "would free approximately "
	idx := strings.index(stdout, needle)
	if idx < 0 {
		return 0
	}
	rest := stdout[idx + len(needle):]
	end := strings.index(rest, " ")
	if end < 0 {
		return 0
	}
	return parse_human_size(rest[:end])
}

// parse_human_size accepts strings like "1.2GB", "345MB", "12KB", "100B".
@(private)
parse_human_size :: proc(s: string) -> i64 {
	trimmed := strings.trim_space(s)
	if len(trimmed) == 0 {
		return 0
	}
	// Find the boundary between digits/period and unit suffix.
	cut := len(trimmed)
	for r, i in trimmed {
		if !(r == '.' || (r >= '0' && r <= '9')) {
			cut = i
			break
		}
	}
	num_str := trimmed[:cut]
	unit := strings.to_upper(strings.trim_space(trimmed[cut:]), context.temp_allocator)
	value, ok := strconv.parse_f64(num_str)
	if !ok {
		return 0
	}
	mul: f64 = 1
	switch unit {
	case "B":              mul = 1
	case "K", "KB", "KIB": mul = 1024
	case "M", "MB", "MIB": mul = 1024 * 1024
	case "G", "GB", "GIB": mul = 1024 * 1024 * 1024
	case "T", "TB", "TIB": mul = 1024 * 1024 * 1024 * 1024
	}
	return i64(value * mul)
}

// parse_brew_autoremove_packages extracts the package list from
// `brew autoremove --dry-run` output. Format varies across versions; we
// look for tokens after a "Would remove" / "would autoremove" header line.
@(private)
parse_brew_autoremove_packages :: proc(stdout: string, allocator: runtime.Allocator) -> []string {
	pkgs := make([dynamic]string, 0, 8, allocator)
	lines := strings.split(stdout, "\n", allocator)
	in_block := false
	for line in lines {
		trimmed := strings.trim_space(line)
		if trimmed == "" {
			continue
		}
		low := strings.to_lower(trimmed, allocator)
		if strings.contains(low, "would remove") || strings.contains(low, "would autoremove") || strings.contains(low, "would also remove") {
			in_block = true
			continue
		}
		if !in_block {
			continue
		}
		// brew may emit comma-separated or whitespace-separated tokens.
		toks := strings.fields(trimmed, allocator)
		for tok in toks {
			cleaned := strings.trim(tok, ",")
			if cleaned == "" {
				continue
			}
			append(&pkgs, cleaned)
		}
	}
	return pkgs[:]
}
