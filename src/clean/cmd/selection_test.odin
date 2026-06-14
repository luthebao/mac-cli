package clean_cmd

import "core:testing"

import "mc:clean/types"

// The interactive/deep flow only shows a per-file drill-down (→) for categories
// flagged supports_file_selection. The risky, review-each-file categories MUST
// keep that flag so users can pick individual large files and duplicate copies
// instead of nuking the whole category. Pin it.
@(test)
test_file_selectable_categories :: proc(t: ^testing.T) {
	testing.expect(t, types.category_of(.Large_Files).supports_file_selection, "Large Files must be drillable")
	testing.expect(t, types.category_of(.Duplicates).supports_file_selection, "Duplicate Files must be drillable")
	testing.expect(t, types.category_of(.Downloads).supports_file_selection, "Old Downloads must be drillable")
}
