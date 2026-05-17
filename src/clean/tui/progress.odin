package clean_tui

import "core:fmt"
import "core:strings"

// ProgressBar renders a simple [#####    ] X/N bar that overwrites itself.
ProgressBar :: struct {
	total:   int,
	current: int,
	width:   int,
	label:   string,
}

progress_start :: proc(p: ^ProgressBar, total: int, label: string) {
	p.total = total
	p.current = 0
	p.width = 30
	p.label = label
	hide_cursor()
	progress_render(p)
}

progress_advance :: proc(p: ^ProgressBar, step := 1) {
	p.current += step
	progress_render(p)
}

progress_finish :: proc(p: ^ProgressBar) {
	fmt.print("\r\x1b[2K")
	show_cursor()
}

@(private)
progress_render :: proc(p: ^ProgressBar) {
	if p.total <= 0 {
		fmt.printf("\r%s  …", p.label)
		return
	}
	pct := f64(p.current) / f64(p.total)
	if pct > 1 { pct = 1 }
	filled := int(pct * f64(p.width))

	b := strings.builder_make(0, p.width + 32, context.temp_allocator)
	strings.write_string(&b, "\r")
	strings.write_string(&b, p.label)
	strings.write_string(&b, " [")
	for i in 0..<p.width {
		if i < filled {
			strings.write_string(&b, "█")
		} else {
			strings.write_string(&b, " ")
		}
	}
	strings.write_string(&b, "] ")
	fmt.sbprintf(&b, "%d/%d", p.current, p.total)
	fmt.print(strings.to_string(b))
}
