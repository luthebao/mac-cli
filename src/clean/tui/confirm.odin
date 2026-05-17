package clean_tui

import "core:fmt"

// confirm prompts "[Y/n]" (when default_yes=true) and returns user's choice.
// Pressing Enter accepts the default.
confirm :: proc(question: string, default_yes := true) -> bool {
	prompt := "[Y/n]"
	if !default_yes {
		prompt = "[y/N]"
	}
	fmt.printf("%s %s ", question, prompt)

	if !enter_raw() {
		// No TTY — fall back to default.
		fmt.println()
		return default_yes
	}
	defer restore()

	for {
		k := read_key()
		#partial switch k {
		case .Enter:
			fmt.println()
			return default_yes
		case .Char:
			c := last_char()
			if c == 'y' || c == 'Y' {
				fmt.println("y")
				return true
			}
			if c == 'n' || c == 'N' {
				fmt.println("n")
				return false
			}
		case .Ctrl_C, .Ctrl_D, .Esc:
			fmt.println()
			return false
		}
	}
}
