package shot

import "core:c"

// Minimal CoreGraphics + CoreFoundation bindings — just enough to look up
// the CGWindowID of an app's frontmost on-screen window. We do this from
// scratch (no Cocoa wrapper crate) because the surface is tiny:
//   - CGWindowListCopyWindowInfo  → returns a CFArray of CFDictionaries
//   - CFArrayGetCount/AtIndex      → iterate the array
//   - CFDictionaryGetValue         → read fields keyed by CFStringRef globals
//   - CFNumberGetValue             → unbox PID / layer / window number
//   - CFRelease                    → drop the array (we own it; "Copy" rule)

foreign import core_graphics "system:CoreGraphics.framework"
foreign import core_foundation "system:CoreFoundation.framework"

CFTypeRef       :: distinct rawptr
CFArrayRef      :: distinct rawptr
CFDictionaryRef :: distinct rawptr
CFNumberRef     :: distinct rawptr
CFStringRef     :: distinct rawptr

CFIndex    :: c.long
CGWindowID :: c.uint

// CGWindowListCopyWindowInfo option bits (CGWindow.h).
@(private="file") OPT_ON_SCREEN_ONLY       :: u32(1)
@(private="file") OPT_EXCLUDE_DESKTOP      :: u32(0x10)
@(private="file") NULL_WINDOW              :: CGWindowID(0)

// CFNumberType — kCFNumberSInt32Type. PIDs/layers/window-numbers are stored
// as 32-bit ints in the window-info dictionaries.
@(private="file") CF_NUMBER_SINT32 :: c.int(3)

@(default_calling_convention="c")
foreign core_graphics {
	CGWindowListCopyWindowInfo :: proc(option: u32, relative_to: CGWindowID) -> CFArrayRef ---

	// const CFStringRef globals — the keys for the window-info dictionaries.
	kCGWindowOwnerPID: CFStringRef
	kCGWindowNumber:   CFStringRef
	kCGWindowLayer:    CFStringRef
}

@(default_calling_convention="c")
foreign core_foundation {
	CFArrayGetCount        :: proc(array: CFArrayRef) -> CFIndex ---
	CFArrayGetValueAtIndex :: proc(array: CFArrayRef, idx: CFIndex) -> rawptr ---
	CFDictionaryGetValue   :: proc(dict: CFDictionaryRef, key: rawptr) -> rawptr ---
	CFNumberGetValue       :: proc(number: CFNumberRef, type: c.int, value_ptr: rawptr) -> b32 ---
	CFRelease              :: proc(cf: CFTypeRef) ---
}

// find_window_id returns the CGWindowID of the on-screen window owned by
// `pid` that is most likely the app's main UI:
//   1. Prefer the frontmost layer-0 window (normal app window).
//   2. Fall back to the first non-desktop window of any layer.
//   3. Return 0 if the app has no on-screen window (minimized, agent-only, …).
//
// CGWindowListCopyWindowInfo returns windows in front-to-back order, so the
// first match in iteration order is the topmost.
find_window_id :: proc(pid: int) -> CGWindowID {
	list := CGWindowListCopyWindowInfo(OPT_ON_SCREEN_ONLY | OPT_EXCLUDE_DESKTOP, NULL_WINDOW)
	if list == nil {
		return 0
	}
	defer CFRelease(CFTypeRef(list))

	n := CFArrayGetCount(list)
	target := i32(pid)
	fallback: CGWindowID = 0

	for i in 0..<n {
		entry := CFArrayGetValueAtIndex(list, i)
		if entry == nil {
			continue
		}
		dict := CFDictionaryRef(entry)

		if dict_i32(dict, rawptr(kCGWindowOwnerPID)) != target {
			continue
		}
		wnum := dict_i32(dict, rawptr(kCGWindowNumber))
		if wnum <= 0 {
			continue
		}

		if dict_i32(dict, rawptr(kCGWindowLayer)) == 0 {
			return CGWindowID(wnum)
		}
		if fallback == 0 {
			fallback = CGWindowID(wnum)
		}
	}
	return fallback
}

@(private="file")
dict_i32 :: proc(dict: CFDictionaryRef, key: rawptr) -> i32 {
	v := CFDictionaryGetValue(dict, key)
	if v == nil {
		return -1
	}
	out: i32 = 0
	if CFNumberGetValue(CFNumberRef(v), CF_NUMBER_SINT32, &out) {
		return out
	}
	return -1
}
