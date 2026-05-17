package clean_tui

import "core:fmt"
import "core:thread"
import "core:time"

// Spinner is a small animated ticker for during scans. Start, do work,
// Stop. Not goroutine-safe across multiple instances.
Spinner :: struct {
	label:   string,
	running: bool,
	t:       ^thread.Thread,
}

@(private="file")
g_frames := [?]string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

spinner_start :: proc(s: ^Spinner, label: string) {
	s.label = label
	s.running = true
	hide_cursor()
	s.t = thread.create_and_start_with_poly_data(s, proc(s: ^Spinner) {
		i := 0
		for s.running {
			frame := g_frames[i % len(g_frames)]
			fmt.printf("\r%s %s", frame, s.label)
			time.sleep(80 * time.Millisecond)
			i += 1
		}
	})
}

spinner_stop :: proc(s: ^Spinner) {
	s.running = false
	if s.t != nil {
		thread.join(s.t)
		thread.destroy(s.t)
		s.t = nil
	}
	fmt.print("\r\x1b[2K") // clear the spinner line
	show_cursor()
}
