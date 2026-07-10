package clop

import "mc:sysx"

// Tool is one external CLI we shell out to. `bin` is the command we'll
// exec (looked up on $PATH via `which`); `brew_pkg` is the Homebrew formula
// the user needs to install if missing. We don't bundle these — they're
// large, licensed differently, and brew is the canonical install path
// for them on macOS.
Tool :: struct {
	bin:      string,
	brew_pkg: string,
}

PNGQUANT      :: Tool{bin = "pngquant",      brew_pkg = "pngquant"}
JPEGOPTIM     :: Tool{bin = "jpegoptim",     brew_pkg = "jpegoptim"}
GIFSICLE      :: Tool{bin = "gifsicle",      brew_pkg = "gifsicle"}
FFMPEG        :: Tool{bin = "ffmpeg",        brew_pkg = "ffmpeg"}
VIPSTHUMBNAIL :: Tool{bin = "vipsthumbnail", brew_pkg = "vips"}
VIPSHEADER    :: Tool{bin = "vipsheader",    brew_pkg = "vips"}
CWEBP         :: Tool{bin = "cwebp",         brew_pkg = "webp"}
HEIF_ENC      :: Tool{bin = "heif-enc",      brew_pkg = "libheif"}
EXIFTOOL      :: Tool{bin = "exiftool",      brew_pkg = "exiftool"}

// tool_present is the bare which check, with no user-facing output. Used
// by both ensure_tools and the post-install re-probe in install.odin.
tool_present :: proc(t: Tool) -> bool {
	r := sysx.run_capture({"/usr/bin/which", t.bin}, context.temp_allocator)
	return r.ok && r.stdout != ""
}

// ensure_tools accepts a batch of required tools and either confirms they
// are all present, or — on miss — prompts the user once for a combined
// `brew install A B C` (see install.odin). De-duplicates inputs by bin
// name so callers can pass the same Tool twice without spamming brew.
//
// Returns true iff every input tool is on $PATH after this call.
ensure_tools :: proc(needed: []Tool) -> bool {
	seen := make(map[string]bool, len(needed), context.temp_allocator)
	missing := make([dynamic]Tool, 0, len(needed), context.temp_allocator)
	for t in needed {
		if seen[t.bin] { continue }
		seen[t.bin] = true
		if !tool_present(t) {
			append(&missing, t)
		}
	}
	if len(missing) == 0 {
		return true
	}
	return prompt_install_missing(missing[:])
}

// ensure_tool keeps the single-tool signature for any caller that wants
// it. Internally it goes through ensure_tools, so the user gets the same
// brew-install prompt UX.
ensure_tool :: proc(t: Tool) -> bool {
	tools := [1]Tool{t}
	return ensure_tools(tools[:])
}

// available_tools offers one combined brew-install prompt for whatever is
// missing from `needed`, then probes each distinct tool once and returns
// bin → present. Callers use the map to skip individual files whose tool is
// unavailable — a declined install for one format must not abort the
// formats whose tools ARE ready.
available_tools :: proc(needed: []Tool) -> map[string]bool {
	_ = ensure_tools(needed)
	avail := make(map[string]bool, len(needed), context.temp_allocator)
	for t in needed {
		if t.bin in avail { continue }
		avail[t.bin] = tool_present(t)
	}
	return avail
}
