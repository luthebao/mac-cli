package clean_tui

import "core:strings"

import "mc:clean/types"
import "mc:fsx"

// explore opens a drill-down picker over `parent_items` (the items the user
// drilled into from a category row). Lets them tick which to keep selected,
// or `←` back out. Returned bool slice has the same length as parent_items
// — true means "selected for cleaning". absolute_paths shows full paths
// instead of ~-abbreviated ones (the -A flag / config setting).
explore :: proc(category_name: string, parent_items: []types.CleanableItem, absolute_paths := false) -> (selected: []bool, cancelled: bool) {
	rows := make([]CheckboxItem, len(parent_items), context.temp_allocator)
	for item, i in parent_items {
		rows[i] = CheckboxItem{
			label = absolute_paths ? item.path : abbreviate_path(item.path),
			hint  = fsx.format_size(item.size, context.temp_allocator),
		}
	}

	title := strings.concatenate({"Browsing: ", category_name}, context.temp_allocator)
	result, _ := checkbox(title, rows)
	if result == .Cancelled {
		return nil, true
	}

	out := make([]bool, len(parent_items))
	for r, i in rows {
		out[i] = r.selected
	}
	return out, false
}

@(private)
abbreviate_path :: proc(path: string) -> string {
	return fsx.abbreviate(path, context.temp_allocator)
}
