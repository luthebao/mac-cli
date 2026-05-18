package clop

// Quality presets for -o (optimise in place). Two profiles: default (what
// Clop calls "lossless-ish, ~30-50% reduction") and aggressive (what Clop
// switches to under -a, ~60-85% reduction). Values come straight from the
// Clop source — see Clop/Images.swift and Clop/Video.swift.

Preset :: struct {
	pngquant_quality:  string, // pngquant `--quality MIN-MAX` (e.g. "0-100")
	jpegoptim_max:     int,    // jpegoptim `--max N`
	gifsicle_opt:      int,    // gifsicle `-ON` (1, 2, or 3)
	gifsicle_lossy:    int,    // gifsicle `--lossy=N`
	gifsicle_colors:   int,    // gifsicle `--colors=N` (0 = omit flag)
	ffmpeg_q:          int,    // h264_videotoolbox `-q:v N` (default profile)
	ffmpeg_crf:        int,    // software h264 `-crf N` (aggressive profile)
	ffmpeg_preset:     string, // software h264 `-preset slower` (aggressive)
	use_software_h264: bool,   // true → use crf path; false → videotoolbox
}

// PRESET_DEFAULT mirrors Clop's non-aggressive defaults.
PRESET_DEFAULT :: Preset{
	pngquant_quality  = "0-100",
	jpegoptim_max     = 85,
	gifsicle_opt      = 2,
	gifsicle_lossy    = 30,
	gifsicle_colors   = 0,
	ffmpeg_q          = 45,
	ffmpeg_crf        = 0,
	ffmpeg_preset     = "",
	use_software_h264 = false, // hardware encode via videotoolbox
}

// PRESET_AGGRESSIVE mirrors Clop's `-a` aggressive defaults.
PRESET_AGGRESSIVE :: Preset{
	pngquant_quality  = "0-85",
	jpegoptim_max     = 68,
	gifsicle_opt      = 3,
	gifsicle_lossy    = 80,
	gifsicle_colors   = 256,
	ffmpeg_q          = 0,
	ffmpeg_crf        = 26,
	ffmpeg_preset     = "slower",
	use_software_h264 = true,
}

pick_preset :: proc(aggressive: bool) -> Preset {
	return PRESET_AGGRESSIVE if aggressive else PRESET_DEFAULT
}
