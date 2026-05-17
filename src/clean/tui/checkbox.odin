package clean_tui

import "core:fmt"
import "core:strings"

import "mc:util"

// CheckboxItem is one row in the checkbox widget. Right-arrow drill-down is
// available iff supports_drill is true; selected/disabled tweak the marker.
CheckboxItem :: struct {
	label:          string,
	hint:           string, // optional dim text shown to the right
	supports_drill: bool,
	selected:       bool,
	disabled:       bool,   // shown but not selectable
}

CheckboxResult :: enum {
	Submitted,  // user pressed Enter
	Cancelled,  // user pressed q / Ctrl-C / Esc
	Drill_Down, // user pressed → on a drill-capable row
}

// checkbox runs the multi-select widget. Mutates items[].selected in place.
// Returns:
//   - Submitted with drill_index = -1
//   - Drill_Down with drill_index = the focused item
//   - Cancelled with drill_index = -1
checkbox :: proc(title: string, items: []CheckboxItem) -> (result: CheckboxResult, drill_index: int) {
	if !enter_raw() {
		// No TTY; auto-submit current state.
		return .Submitted, -1
	}
	defer restore()
	hide_cursor()
	defer show_cursor()

	cursor := 0
	height_lines := len(items) + 3 // title + items + hint line

	render_checkbox(title, items, cursor)
	for {
		k := read_key()
		#partial switch k {
		case .Up:
			cursor = (cursor - 1 + len(items)) % len(items)
		case .Down:
			cursor = (cursor + 1) % len(items)
		case .Space:
			if !items[cursor].disabled {
				items[cursor].selected = !items[cursor].selected
			}
		case .Char:
			c := last_char()
			switch c {
			case 'a':
				// Select all (skipping disabled).
				for &item in items {
					if !item.disabled {
						item.selected = true
					}
				}
			case 'i':
				// Invert.
				for &item in items {
					if !item.disabled {
						item.selected = !item.selected
					}
				}
			case 'q':
				clear_lines(height_lines)
				return .Cancelled, -1
			}
		case .Right:
			if items[cursor].supports_drill {
				clear_lines(height_lines)
				return .Drill_Down, cursor
			}
		case .Enter:
			clear_lines(height_lines)
			return .Submitted, -1
		case .Ctrl_C, .Ctrl_D, .Esc:
			clear_lines(height_lines)
			return .Cancelled, -1
		}
		clear_lines(height_lines)
		render_checkbox(title, items, cursor)
	}
}

@(private)
render_checkbox :: proc(title: string, items: []CheckboxItem, cursor: int) {
	fmt.println(util.bold(title))
	for item, i in items {
		marker := "[ ]"
		if item.selected {
			marker = util.green("[x]", context.temp_allocator)
		}
		arrow := "  "
		if i == cursor {
			arrow = util.cyan("→ ", context.temp_allocator)
		}
		drill := ""
		if item.supports_drill {
			drill = util.dim(" →", context.temp_allocator)
		}
		hint := ""
		if item.hint != "" {
			hint_text := strings.concatenate({"  ", item.hint}, context.temp_allocator)
			hint = util.dim(hint_text, context.temp_allocator)
		}
		fmt.printfln("%s%s %s%s%s", arrow, marker, item.label, drill, hint)
	}
	fmt.println(util.dim("↑↓ navigate · space toggle · a all · i invert · → drill · ⏎ submit · q quit"))
}
