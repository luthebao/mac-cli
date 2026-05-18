package clop

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "mc:sysx"
import "mc:util"

// run_downscale dispatches `-d <factor>`. Images use vipsthumbnail (-s
// computed-WxH), videos use ffmpeg -vf scale=W:H (with the -2 trick to
// keep the height even and avoid h264 encoder errors on odd dimensions).
run_downscale :: proc(opts: Options) -> int {
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

	if !preflight_downscale(files) {
		return 1
	}

	processed, skipped, failed := 0, 0, 0
	for path in files {
		kind := classify(path)
		ok_file := false
		switch {
		case is_image(kind): ok_file = downscale_image(path, opts.factor, opts.keep_orig)
		case is_video(kind): ok_file = downscale_video(path, opts.factor, opts.keep_orig)
		case:                skipped += 1; continue
		}
		if ok_file { processed += 1 } else { failed += 1 }
	}
	report_summary(processed, skipped, failed)
	return 0 if failed == 0 else 1
}

@(private)
preflight_downscale :: proc(files: []string) -> bool {
	needed := make([dynamic]Tool, 0, 3, context.temp_allocator)
	any_image, any_video := false, false
	for f in files {
		k := classify(f)
		if is_image(k) { any_image = true }
		if is_video(k) { any_video = true }
	}
	if any_image {
		append(&needed, VIPSTHUMBNAIL, VIPSHEADER)
	}
	if any_video {
		append(&needed, FFMPEG)
	}
	return ensure_tools(needed[:])
}

// downscale_image: vipsthumbnail uses pixel count as `-s W` (max edge).
// To scale by a fraction we read the current size via vipsheader, multiply,
// and pass the new max-edge. Output filename pattern `%s.clop.tmp.<ext>`
// is recombined with the original path.
//
// vipsthumbnail expects a "size" string like "1280x720" or "1280" (max
// width). We pass WIDTHx0 (height=0 → preserve aspect) by computing W
// from the source dimensions.
@(private)
downscale_image :: proc(path: string, factor: f64, keep_orig: bool) -> bool {
	w, h, ok := image_dimensions(path)
	if !ok {
		fmt.eprintfln("  %s  %s (could not read dimensions)",
			util.yellow("fail", context.temp_allocator), path)
		return false
	}
	new_w := int(f64(w) * factor)
	new_h := int(f64(h) * factor)
	if new_w < 2 || new_h < 2 {
		fmt.eprintfln("  %s  %s (factor produces a degenerate size)",
			util.yellow("fail", context.temp_allocator), path)
		return false
	}
	if keep_orig && !backup_file(path) { return false }

	size_arg := fmt.tprintf("%dx%d", new_w, new_h)
	// vipsthumbnail writes to `<input>_<size>.<ext>` by default; we use -o
	// with an explicit template so we know the output path.
	dir := filepath.dir(path)
	base := filepath.base(path)
	stem := strings.trim_suffix(base, filepath.ext(base))
	ext := filepath.ext(base)
	tmp_name := fmt.tprintf("%s.clop.tmp%s", stem, ext)
	tmp_path, _ := filepath.join({dir, tmp_name}, context.temp_allocator)

	// `-o` template uses %s for the stem; pass the explicit tmp stem.
	args := []string{
		"vipsthumbnail",
		path,
		"-s", size_arg,
		"-o", strings.concatenate({tmp_path, "[Q=100]"}, context.temp_allocator),
	}
	if !sysx.run_quiet(args) {
		os.remove(tmp_path)
		fmt.eprintfln("  %s  %s", util.yellow("fail", context.temp_allocator), path)
		return false
	}
	if err := os.rename(tmp_path, path); err != nil {
		os.remove(tmp_path)
		fmt.eprintfln("  %s  %s (rename failed)", util.yellow("fail", context.temp_allocator), path)
		return false
	}
	report_done(path)
	return true
}

// downscale_video: ffmpeg -vf scale=W:-2. The -2 keeps height even
// (h264 requires even dimensions); we compute the target width from the
// factor and let ffmpeg handle the rest. Encoder uses videotoolbox.
@(private)
downscale_video :: proc(path: string, factor: f64, keep_orig: bool) -> bool {
	w, h, ok := video_dimensions(path)
	if !ok {
		fmt.eprintfln("  %s  %s (could not read dimensions)",
			util.yellow("fail", context.temp_allocator), path)
		return false
	}
	_ = h
	new_w := int(f64(w) * factor)
	if new_w % 2 == 1 { new_w -= 1 }
	if new_w < 2 {
		fmt.eprintfln("  %s  %s (factor produces a degenerate width)",
			util.yellow("fail", context.temp_allocator), path)
		return false
	}
	if keep_orig && !backup_file(path) { return false }

	ext := filepath.ext(path)
	if ext == "" { ext = ".mp4" }
	tmp := strings.concatenate({path, ".clop.tmp", ext}, context.temp_allocator)

	vf := fmt.tprintf("scale=%d:-2", new_w)
	args := []string{
		"ffmpeg", "-y", "-i", path,
		"-vf", vf,
		"-vcodec", "h264_videotoolbox", "-tag:v", "avc1", "-q:v", "45",
		"-c:a", "copy",
		"-movflags", "+faststart",
		"-hide_banner", "-loglevel", "error",
		tmp,
	}
	if !sysx.run_quiet(args) {
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

// image_dimensions shells out to `vipsheader -f Xsize` / `-f Ysize`. These
// are tiny calls — vips loads the header only, not the pixels.
@(private)
image_dimensions :: proc(path: string) -> (w, h: int, ok: bool) {
	wr := sysx.run_capture({"vipsheader", "-f", "Xsize", path}, context.temp_allocator)
	hr := sysx.run_capture({"vipsheader", "-f", "Ysize", path}, context.temp_allocator)
	if !wr.ok || !hr.ok { return }
	ww := parse_int(strings.trim_space(wr.stdout))
	hh := parse_int(strings.trim_space(hr.stdout))
	if ww <= 0 || hh <= 0 { return }
	return ww, hh, true
}

// video_dimensions uses ffprobe. We pull width and height as a single
// "WxH" stream entry to keep the call count down.
@(private)
video_dimensions :: proc(path: string) -> (w, h: int, ok: bool) {
	r := sysx.run_capture({
		"ffprobe", "-v", "error",
		"-select_streams", "v:0",
		"-show_entries", "stream=width,height",
		"-of", "csv=s=x:p=0",
		path,
	}, context.temp_allocator)
	if !r.ok { return }
	parts := strings.split(strings.trim_space(r.stdout), "x", context.temp_allocator)
	if len(parts) < 2 { return }
	ww := parse_int(parts[0])
	hh := parse_int(parts[1])
	if ww <= 0 || hh <= 0 { return }
	return ww, hh, true
}

@(private)
parse_int :: proc(s: string) -> int {
	n := 0
	for r in s {
		if r < '0' || r > '9' { return -1 }
		n = n * 10 + int(r - '0')
	}
	return n
}
