package clop

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "mc:sysx"
import "mc:util"

// run_optimise dispatches `-o`. Accepts images, videos, and PDFs (PDFs
// deferred — currently skipped with a hint). Walks `target_path` (file or
// directory) and calls the per-format helper for each match.
run_optimise :: proc(opts: Options) -> int {
	accept :: proc(k: Kind) -> bool { return k != .Unsupported }
	files, ok := expand_target(opts.target_path, accept, opts.recursive, context.temp_allocator)
	if !ok {
		fmt.eprintfln("mac-cli clop: cannot read %q", opts.target_path)
		return 1
	}
	if len(files) == 0 {
		fmt.println(util.dim("clop: no supported files found.", context.temp_allocator))
		return 0
	}

	// Pre-flight: probe tool availability based on what extensions we found,
	// so the user sees one "brew install" hint instead of N per-file errors.
	// Files whose tool is still missing afterwards are skipped individually —
	// one absent tool (say ffmpeg for a stray .mp4) must not abort the whole
	// batch of formats that are ready to go.
	needed := make([dynamic]Tool, 0, 4, context.temp_allocator)
	for f in files {
		if t, has_tool := tool_for_optimise(classify(f)); has_tool {
			append(&needed, t)
		}
	}
	avail := available_tools(needed[:])

	preset := pick_preset(opts.aggressive)
	processed, skipped, failed := 0, 0, 0

	for path in files {
		kind := classify(path)
		if t, has_tool := tool_for_optimise(kind); has_tool && !avail[t.bin] {
			fmt.eprintfln("  %s  %s",
				util.dim("skip", context.temp_allocator),
				util.dim(fmt.tprintf("%s (%s not installed)", path, t.bin), context.temp_allocator))
			skipped += 1
			continue
		}
		ok_file := false
		#partial switch kind {
		case .Png:                 ok_file = optimise_png(path, preset, opts.keep_orig)
		case .Jpeg:                ok_file = optimise_jpeg(path, preset, opts.keep_orig)
		case .Gif:                 ok_file = optimise_gif(path, preset, opts.keep_orig)
		case .Mp4, .Mov:           ok_file = optimise_video(path, preset, opts.keep_orig)
		case .Pdf:
			fmt.eprintfln("  %s  %s",
				util.dim("skip", context.temp_allocator),
				util.dim(fmt.tprintf("%s (PDF optimisation not yet implemented)", path), context.temp_allocator))
			skipped += 1
			continue
		case:
			skipped += 1
			continue
		}
		if ok_file {
			processed += 1
		} else {
			failed += 1
		}
	}

	report_summary(processed, skipped, failed)
	return 0 if failed == 0 else 1
}

// tool_for_optimise maps a file kind to the CLI tool -o needs for it.
@(private)
tool_for_optimise :: proc(k: Kind) -> (Tool, bool) {
	#partial switch k {
	case .Png:       return PNGQUANT, true
	case .Jpeg:      return JPEGOPTIM, true
	case .Gif:       return GIFSICLE, true
	case .Mp4, .Mov: return FFMPEG, true
	}
	return {}, false
}

// optimise_png:  pngquant --force --quality {min-max} --ext .png {path}
// `--ext .png` overwrites the input in place (matches Clop behaviour).
@(private)
optimise_png :: proc(path: string, preset: Preset, keep_orig: bool) -> bool {
	if keep_orig && !backup_file(path) { return false }
	args := []string{
		"pngquant",
		"--force",
		"--quality", preset.pngquant_quality,
		"--ext", ".png",
		path,
	}
	return run_op(args, path)
}

// optimise_jpeg: jpegoptim --keep-all --force --max N --auto-mode
//                          --overwrite --dest {dir} {path}
// `--overwrite --dest <dir>` writes the optimised file beside the original
// at the same name; jpegoptim treats that as in-place when dest == dir.
@(private)
optimise_jpeg :: proc(path: string, preset: Preset, keep_orig: bool) -> bool {
	if keep_orig && !backup_file(path) { return false }
	dir := filepath.dir(path)
	max_str := fmt.tprintf("%d", preset.jpegoptim_max)
	args := []string{
		"jpegoptim",
		"--keep-all",
		"--force",
		"--max", max_str,
		"--auto-mode",
		"--overwrite",
		"--dest", dir,
		path,
	}
	return run_op(args, path)
}

// optimise_gif: gifsicle -O{N} --lossy=N [--colors=256] -o {tmp} {path}
// gifsicle won't overwrite the input directly, so we write to a sibling
// temp and rename. Threads omitted — single-file CLI runs don't need them.
@(private)
optimise_gif :: proc(path: string, preset: Preset, keep_orig: bool) -> bool {
	if keep_orig && !backup_file(path) { return false }
	tmp := strings.concatenate({path, ".clop.tmp"}, context.temp_allocator)

	opt_flag   := fmt.tprintf("-O%d", preset.gifsicle_opt)
	lossy_flag := fmt.tprintf("--lossy=%d", preset.gifsicle_lossy)

	args := make([dynamic]string, 0, 8, context.temp_allocator)
	append(&args, "gifsicle", opt_flag, lossy_flag)
	if preset.gifsicle_colors > 0 {
		append(&args, fmt.tprintf("--colors=%d", preset.gifsicle_colors))
	}
	append(&args, "--output", tmp, path)

	if !sysx.run_quiet(args[:]) {
		os.remove(tmp)
		fmt.eprintfln("  %s  %s", util.yellow("fail", context.temp_allocator), path)
		return false
	}
	if err := os.rename(tmp, path); err != nil {
		os.remove(tmp)
		fmt.eprintfln("  %s  %s (rename failed)", util.yellow("fail", context.temp_allocator), path)
		return false
	}
	report_done(path)
	return true
}

// optimise_video: ffmpeg -y -i {path} -vcodec ... -tag:v avc1
//                        -movflags +faststart {tmp}
// Hardware (videotoolbox) by default, software h264 with -crf for -a.
// On non-arm64 builds the binary won't be shipped, but the encoder path
// here works if someone builds locally for x86_64.
@(private)
optimise_video :: proc(path: string, preset: Preset, keep_orig: bool) -> bool {
	if keep_orig && !backup_file(path) { return false }
	ext := filepath.ext(path)
	if ext == "" { ext = ".mp4" }
	tmp := strings.concatenate({path, ".clop.tmp", ext}, context.temp_allocator)

	args := make([dynamic]string, 0, 16, context.temp_allocator)
	append(&args, "ffmpeg", "-y", "-i", path)

	if preset.use_software_h264 {
		append(&args, "-vcodec", "h264", "-tag:v", "avc1",
			"-preset", preset.ffmpeg_preset,
			"-crf", fmt.tprintf("%d", preset.ffmpeg_crf))
	} else {
		append(&args, "-vcodec", "h264_videotoolbox", "-tag:v", "avc1",
			"-q:v", fmt.tprintf("%d", preset.ffmpeg_q))
	}
	append(&args, "-c:a", "copy", "-movflags", "+faststart",
		"-hide_banner", "-loglevel", "error", tmp)

	if !sysx.run_quiet(args[:]) {
		os.remove(tmp)
		fmt.eprintfln("  %s  %s", util.yellow("fail", context.temp_allocator), path)
		return false
	}
	if err := os.rename(tmp, path); err != nil {
		os.remove(tmp)
		fmt.eprintfln("  %s  %s (rename failed)", util.yellow("fail", context.temp_allocator), path)
		return false
	}
	report_done(path)
	return true
}

// run_op is the shared "run subprocess, print outcome line" helper for the
// PNG/JPEG cases that don't need a temp-file dance (pngquant overwrites
// in place; jpegoptim writes to --dest at the same name).
@(private)
run_op :: proc(args: []string, path: string) -> bool {
	if !sysx.run_quiet(args) {
		fmt.eprintfln("  %s  %s", util.yellow("fail", context.temp_allocator), path)
		return false
	}
	report_done(path)
	return true
}

// backup_file copies foo.png to foo.png.orig before we overwrite. We use
// the `.orig` suffix (not `.bak`) so users can restore with a single
// `mv foo.png.orig foo.png`. Returns false if the copy fails — in which
// case we abort the op rather than risk an irreversible overwrite.
@(private)
backup_file :: proc(path: string) -> bool {
	dst := strings.concatenate({path, ".orig"}, context.temp_allocator)
	if !sysx.run_quiet({"/bin/cp", "-p", path, dst}) {
		fmt.eprintfln("  %s  %s (backup failed; aborting)", util.yellow("fail", context.temp_allocator), path)
		return false
	}
	return true
}

@(private)
report_done :: proc(path: string) {
	before, after := size_pair(path)
	if before == 0 {
		fmt.printfln("  %s  %s", util.green("done", context.temp_allocator), path)
		return
	}
	pct := 0
	if before > 0 {
		pct = int(100 - (after * 100 / before))
	}
	// pct can be negative when the "optimized" output grew (pngquant --force
	// et al. overwrite even then) — show "(+N%)", not the garbled "(--N%)".
	delta := pct >= 0 ? fmt.tprintf("(-%d%%)", pct) : fmt.tprintf("(+%d%%)", -pct)
	fmt.printfln("  %s  %s  %s",
		util.green("done", context.temp_allocator),
		path,
		util.dim(delta, context.temp_allocator))
}

// size_pair reads the post-op file size paired with the size of the .orig
// backup (if -k was used). When -k wasn't used we don't know the pre-size,
// so we return (0, after) and the caller suppresses the % delta.
@(private)
size_pair :: proc(path: string) -> (before, after: i64) {
	orig := strings.concatenate({path, ".orig"}, context.temp_allocator)
	if fi, err := os.stat(orig, context.temp_allocator); err == nil {
		before = fi.size
	}
	if fi, err := os.stat(path, context.temp_allocator); err == nil {
		after = fi.size
	}
	return
}
