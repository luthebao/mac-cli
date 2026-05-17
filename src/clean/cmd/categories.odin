package clean_cmd

import "core:fmt"
import "core:strings"

import "mc:clean/types"
import "mc:util"

// run_categories prints all registered categories grouped by safety level.
run_categories :: proc(args: []string) -> int {
	groups := [3]types.Safety{ .Safe, .Moderate, .Risky }
	icons := [3]string{ "🟢", "🟡", "🔴" }
	headers := [3]string{ "Safe", "Moderate", "Risky" }

	fmt.println(util.bold("Available cleanup categories"))
	fmt.println()

	for safety, i in groups {
		header := fmt.aprintf("%s %s", icons[i], headers[i], allocator = context.temp_allocator)
		fmt.println(util.bold(header))
		for c in types.CATEGORIES {
			if c.safety != safety {
				continue
			}
			slug := util.cyan(fmt.aprintf("%-18s", c.slug, allocator = context.temp_allocator))
			name := fmt.aprintf("%-26s", c.name, allocator = context.temp_allocator)
			group := util.gray(fmt.aprintf("[%s]", types.group_label(c.group), allocator = context.temp_allocator))
			fmt.printfln("  %s  %s  %s  %s", slug, name, group, c.description)
			if c.safety_note != "" {
				note := strings.concatenate({"     ↳ ", c.safety_note}, context.temp_allocator)
				fmt.println(util.dim(note))
			}
		}
		fmt.println()
	}

	fmt.println(util.dim(fmt.aprintf("Total: %d categories", len(types.CATEGORIES), allocator = context.temp_allocator)))
	return 0
}
