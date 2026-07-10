package clop

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "mc:sysx"
import "mc:util"

// CONVERT_QUALITY mirrors Clop's CLI default (60). Same value used for
// every target format — cwebp/heif_enc both take a 0..100 scale.
CONVERT_QUALITY :: 60

// run_convert dispatches `-c <format>`. Image-only; videos would need a
// codec-target choice we haven't designed yet.
run_convert :: proc(opts: Options) -> int {
	accept :: proc(k: Kind) -> bool { return is_image(k) }
	files, ok := expand_target(opts.target_path, accept, opts.recursive, context.temp_allocator)
	if !ok {
		fmt.eprintfln("mac-cli clop: cannot read %q", opts.target_path)
		return 1
	}
	if len(files) == 0 {
		fmt.println(util.dim("clop: no supported images found.", context.temp_allocator))
		return 0
	}

	// Only one tool per target format, but still go through ensure_tools so
	// the user gets the same brew-install prompt behaviour as -o / -d.
	needed := make([dynamic]Tool, 0, 1, context.temp_allocator)
	switch opts.to_format {
	case "webp":            append(&needed, CWEBP)
	case "heic", "avif":    append(&needed, HEIF_ENC)
	}
	if !ensure_tools(needed[:]) { return 1 }

	processed, skipped, failed := 0, 0, 0
	for path in files {
		if convert_one(path, opts.to_format) {
			processed += 1
		} else {
			failed += 1
		}
	}
	report_summary(processed, skipped, failed)
	return 0 if failed == 0 else 1
}

@(private)
convert_one :: proc(path: string, target: string) -> bool {
	dir := filepath.dir(path)
	base := filepath.base(path)
	stem := strings.trim_suffix(base, filepath.ext(base))
	new_name := fmt.tprintf("%s.%s", stem, target)
	out, _ := filepath.join({dir, new_name}, context.temp_allocator)

	// Refuse to clobber an existing target. cwebp/heif-enc will both
	// silently overwrite, which is the wrong default for a CLI invoked
	// against a directory (one stray re-run could destroy hand-edited
	// outputs). User can delete the existing file and retry.
	if _, err := os.stat(out, context.temp_allocator); err == nil {
		fmt.eprintfln("  %s  %s (target %q already exists; delete it to retry)",
			util.yellow("skip", context.temp_allocator), path, out)
		return false
	}

	qstr := fmt.tprintf("%d", CONVERT_QUALITY)
	args: []string
	switch target {
	case "webp":
		// cwebp -mt -q N -sharp_yuv -metadata all in -o out
		args = []string{
			"cwebp", "-mt", "-q", qstr, "-sharp_yuv", "-metadata", "all",
			path, "-o", out,
		}
	case "heic":
		// heif-enc -q N -o out in
		args = []string{"heif-enc", "-q", qstr, "-o", out, path}
	case "avif":
		// heif-enc --avif -q N -o out in
		args = []string{"heif-enc", "--avif", "-q", qstr, "-o", out, path}
	case:
		fmt.eprintfln("  %s  %s (unsupported target %q)",
			util.yellow("fail", context.temp_allocator), path, target)
		return false
	}

	if !sysx.run_quiet(args) {
		os.remove(out)
		fmt.eprintfln("  %s  %s", util.yellow("fail", context.temp_allocator), path)
		return false
	}
	fmt.printfln("  %s  %s → %s", util.green("done", context.temp_allocator), path, out)
	return true
}
