package clop

import "core:path/filepath"
import "core:strings"

// Kind classifies a file by extension. Unknown extensions are Unsupported
// and are silently skipped when walking directories — that's the point of
// the filter, so a `clop -o ~/Downloads` doesn't choke on .DS_Store etc.
Kind :: enum {
	Unsupported,
	Png,
	Jpeg,
	Gif,
	Mp4,
	Mov,
	Pdf,
}

// classify returns the Kind for a path's extension. Case-insensitive.
classify :: proc(path: string) -> Kind {
	ext := strings.to_lower(filepath.ext(path), context.temp_allocator)
	switch ext {
	case ".png":            return .Png
	case ".jpg", ".jpeg":   return .Jpeg
	case ".gif":            return .Gif
	case ".mp4", ".m4v":    return .Mp4
	case ".mov":            return .Mov
	case ".pdf":            return .Pdf
	}
	return .Unsupported
}

// is_image / is_video are convenience predicates for op handlers that only
// accept a subset (e.g. -c convert is image-only).
is_image :: proc(k: Kind) -> bool {
	#partial switch k {
	case .Png, .Jpeg, .Gif: return true
	}
	return false
}

is_video :: proc(k: Kind) -> bool {
	#partial switch k {
	case .Mp4, .Mov: return true
	}
	return false
}
