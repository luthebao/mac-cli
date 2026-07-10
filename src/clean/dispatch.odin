package clean

import "core:fmt"

import "mc:cli"
import "mc:clean/cmd"

// dispatch routes `mac-cli clean <args...>` to the right subcommand.
// Returns a process exit code (0 = success).
//
// With no args, opens the interactive command menu (cli.pick_at). The menu's
// "interactive" leaf re-enters this proc with args=["interactive"], which
// routes to the scan-and-clean flow. The sentinel exists because empty args
// now means "show menu" — picking the default leaf needs a distinct marker
// or it would infinite-loop back into the menu.
dispatch :: proc(args: []string) -> int {
	if len(args) == 0 {
		chosen, ok := cli.pick_at("clean")
		if !ok { return 0 }
		return dispatch(chosen)
	}

	switch args[0] {
	case "interactive":
		return cmd.run_interactive(args[1:])
	case "categories":
		return cmd.run_categories(args[1:])
	case "config":
		return cmd.run_config(args[1:])
	case "backup":
		return cmd.run_backup(args[1:])
	case "uninstall":
		return cmd.run_uninstall(args[1:])
	case "insights", "analyze":
		return cmd.run_insights(args[1:])
	case "monitor", "status":
		return cmd.run_monitor(args[1:])
	case "deep":
		// Deep-clean preset: scan everything (incl. risky) and pre-select the
		// safe/moderate categories. The sentinel routes into run_interactive.
		return cmd.run_interactive([]string{"--deep"})
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

// print_clean_help delegates to the shared help text in mc:cli so there is
// exactly one source of truth (local copies had already drifted from it).
print_clean_help :: proc() {
	cli.print_help("clean")
}
