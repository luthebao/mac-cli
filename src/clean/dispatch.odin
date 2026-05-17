package clean

import "core:fmt"

import "mc:clean/cmd"

// dispatch routes `mac-cli clean <args...>` to the right subcommand.
// Returns a process exit code (0 = success).
dispatch :: proc(args: []string) -> int {
	if len(args) == 0 {
		return cmd.run_interactive(args)
	}

	switch args[0] {
	case "categories":
		return cmd.run_categories(args[1:])
	case "config":
		return cmd.run_config(args[1:])
	case "backup":
		return cmd.run_backup(args[1:])
	case "uninstall":
		return cmd.run_uninstall(args[1:])
	case "maintenance":
		return cmd.run_maintenance(args[1:])
	case "help", "--help", "-h":
		print_clean_help()
		return 0
	case:
		if len(args[0]) > 0 && args[0][0] == '-' {
			return cmd.run_interactive(args)
		}
		fmt.eprintfln("mac-cli clean: unknown subcommand %q", args[0])
		print_clean_help()
		return 2
	}
}

print_clean_help :: proc() {
	fmt.print(
`mac-cli clean — disk cleaner for macOS

USAGE
  mac-cli clean [flags]
  mac-cli clean <subcommand> [flags]

SUBCOMMANDS
  uninstall, maintenance, categories, config, backup

Run ` + "`mac-cli help clean`" + ` for full details.
`)
}
