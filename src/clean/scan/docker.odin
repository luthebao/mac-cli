package clean_scan

import "base:runtime"
import "core:strings"

import "mc:clean/types"
import "mc:sysx"

// Docker reports a single virtual "item" representing the prunable disk
// usage. Cleaning it shells out to `docker system prune`.
docker_scan :: proc(_: types.ScannerOptions, allocator: runtime.Allocator) -> types.ScanResult {
	cat := types.category_of(.Docker)
	docker := find_docker()
	res: sysx.RunResult
	if docker != "" {
		res = sysx.run_capture({docker, "system", "df"}, context.temp_allocator)
	}
	if docker == "" || !res.ok {
		return types.ScanResult{
			category = cat,
			error    = "docker not available",
		}
	}

	reclaimable := i64(0)
	out := res.stdout
	for line in strings.split_lines_iterator(&out) {
		if strings.contains(line, "RECLAIMABLE") {
			continue
		}
		fields := strings.fields(line, context.temp_allocator)
		// The RECLAIMABLE column renders as "16.43MB (70%)" — and some Docker
		// versions put a space between value and unit ("16.43 MB (70%)").
		// Drop the trailing percentage token, then try the last token alone
		// and joined with its neighbor so both spellings parse.
		n := len(fields)
		for n > 0 && strings.has_prefix(fields[n-1], "(") {
			n -= 1
		}
		if n == 0 {
			continue
		}
		if b, ok := parse_size_token(fields[n-1]); ok {
			reclaimable += b
		} else if n >= 2 {
			joined := strings.concatenate({fields[n-2], fields[n-1]}, context.temp_allocator)
			if jb, jok := parse_size_token(joined); jok {
				reclaimable += jb
			}
		}
	}

	items := make([]types.CleanableItem, 1, allocator)
	items[0] = types.CleanableItem{
		path         = strings.clone("docker://prune", allocator),
		name         = strings.clone("Reclaimable images/containers/build cache", allocator),
		size         = reclaimable,
		is_directory = false,
	}
	return types.ScanResult{
		category   = cat,
		items      = items,
		total_size = reclaimable,
	}
}

docker_clean :: proc(items: []types.CleanableItem, dry_run: bool, allocator: runtime.Allocator) -> types.CleanResult {
	cat := types.category_of(.Docker)
	freed: i64 = 0
	if len(items) > 0 {
		freed = items[0].size
	}
	if dry_run || len(items) == 0 {
		return types.CleanResult{
			category      = cat,
			cleaned_items = len(items),
			freed_bytes   = freed,
		}
	}
	// NB: no --volumes — named volumes hold real user data (databases of
	// stopped compose projects, …) and must never be pruned by a cleaner.
	docker := find_docker()
	if docker == "" || !sysx.run_quiet({docker, "system", "prune", "-af"}) {
		errs := make([]string, 1, allocator)
		errs[0] = strings.clone("docker prune failed", allocator)
		return types.CleanResult{ category = cat, errors = errs }
	}
	return types.CleanResult{
		category      = cat,
		cleaned_items = 1,
		freed_bytes   = freed,
	}
}

// find_docker locates the docker CLI: Docker Desktop's symlink first, then
// whatever is on $PATH. Returns "" when neither responds.
@(private)
find_docker :: proc() -> string {
	if sysx.run_capture({"/usr/local/bin/docker", "--version"}, context.temp_allocator).ok {
		return "/usr/local/bin/docker"
	}
	if sysx.run_capture({"docker", "--version"}, context.temp_allocator).ok {
		return "docker"
	}
	return ""
}

@(private)
parse_size_token :: proc(s: string) -> (bytes: i64, ok: bool) {
	suffix_map := [?]struct{suffix: string, mult: i64}{
		{"TB", 1024 * 1024 * 1024 * 1024},
		{"GB", 1024 * 1024 * 1024},
		{"MB", 1024 * 1024},
		{"kB", 1024},
		{"KB", 1024},
		{"B",  1},
	}
	for entry in suffix_map {
		if strings.has_suffix(s, entry.suffix) {
			num_str := s[:len(s) - len(entry.suffix)]
			f, fok := parse_float(num_str)
			if !fok {
				return 0, false
			}
			return i64(f * f64(entry.mult)), true
		}
	}
	return 0, false
}
