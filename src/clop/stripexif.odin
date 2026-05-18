package clop

import "core:fmt"

import "mc:sysx"
import "mc:util"

// run_stripexif dispatches `-s`. Images + videos via exiftool. We keep
// orientation and resolution (-XResolution/-YResolution=72 -Orientation)
// because dropping them tends to flip portrait phone shots sideways.
run_stripexif :: proc(opts: Options) -> int {
	accept :: proc(k: Kind) -> bool { return is_image(k) || is_video(k) }
	files, ok := expand_target(opts.target_path, accept, opts.recursive, context.temp_allocator)
	if !ok {
		fmt.eprintfln("mac-cli clop: cannot read %q", opts.target_path)
		return 1
	}
	if len(files) == 0 {
		fmt.println(util.dim("clop: no supported files found.", context.temp_allocator))
		return 0
	}
	needed := [1]Tool{EXIFTOOL}
	if !ensure_tools(needed[:]) { return 1 }

	processed, failed := 0, 0
	for path in files {
		if opts.keep_orig && !backup_file(path) { failed += 1; continue }
		args := []string{
			"exiftool",
			"-overwrite_original",
			"-XResolution=72",
			"-YResolution=72",
			"-all=",
			"-tagsFromFile", "@",
			"-XResolution", "-YResolution", "-Orientation",
			path,
		}
		if sysx.run_quiet(args) {
			processed += 1
			fmt.printfln("  %s  %s", util.green("done", context.temp_allocator), path)
		} else {
			failed += 1
			fmt.eprintfln("  %s  %s", util.yellow("fail", context.temp_allocator), path)
		}
	}
	report_summary(processed, 0, failed)
	return 0 if failed == 0 else 1
}
