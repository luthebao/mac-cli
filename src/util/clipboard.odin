package util

import "core:os"
import "core:strings"

import "mc:sysx"

// copy_to_clipboard pipes `text` to macOS's pbcopy. Returns true on success.
copy_to_clipboard :: proc(text: string) -> bool {
	r, w, perr := os.pipe()
	if perr != nil {
		return false
	}
	defer os.close(r)

	desc := os.Process_Desc{
		command = {"/usr/bin/pbcopy"},
		stdin   = r,
	}
	process, serr := os.process_start(desc)
	if serr != nil {
		os.close(w)
		return false
	}

	_, werr := os.write_string(w, text)
	os.close(w)
	if werr != nil {
		_, _ = os.process_wait(process, 0)
		return false
	}
	state, werr2 := os.process_wait(process, 0)
	if werr2 != nil {
		return false
	}
	return state.exited && state.exit_code == 0
}

// paste_from_clipboard returns the current pasteboard text via pbpaste.
paste_from_clipboard :: proc(allocator := context.allocator) -> (text: string, ok: bool) {
	r := sysx.run({"/usr/bin/pbpaste"}, allocator)
	if !r.ok {
		return "", false
	}
	return strings.clone(strings.trim_right_space(r.stdout), allocator), true
}
