package clop

import "core:os"
import "core:path/filepath"
import "core:strings"

// expand_target resolves the user's <path> argument into a list of concrete
// files to process. If path is a file, it's returned as-is (even if its
// extension isn't supported — the op handler will report the mismatch with
// a specific error). If path is a directory, we collect every regular file
// underneath it whose extension matches `accept`.
//
// `recursive` controls whether we descend into subdirectories. Off by
// default to avoid surprise — `clop -o ~/Pictures` shouldn't silently
// re-compress 40 GB of nested photo backups.
expand_target :: proc(
	path:      string,
	accept:    proc(Kind) -> bool,
	recursive: bool,
	allocator := context.allocator,
) -> (files: []string, ok: bool) {
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil {
		return nil, false
	}

	out := make([dynamic]string, 0, 16, allocator)
	if fi.type == .Regular {
		append(&out, strings.clone(path, allocator))
		return out[:], true
	}
	if fi.type != .Directory {
		return out[:], true
	}

	collect_dir(&out, path, accept, recursive, allocator)
	return out[:], true
}

@(private)
collect_dir :: proc(
	out:       ^[dynamic]string,
	dir:       string,
	accept:    proc(Kind) -> bool,
	recursive: bool,
	allocator := context.allocator,
) {
	entries, err := os.read_directory_by_path(dir, -1, context.temp_allocator)
	if err != nil {
		return
	}
	for e in entries {
		#partial switch e.type {
		case .Regular:
			if accept(classify(e.name)) {
				kept, _ := filepath.join({dir, e.name}, allocator)
				append(out, kept)
			}
		case .Directory:
			if recursive {
				sub, _ := filepath.join({dir, e.name}, context.temp_allocator)
				collect_dir(out, sub, accept, recursive, allocator)
			}
		}
	}
}
