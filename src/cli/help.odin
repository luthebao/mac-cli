package cli

import "core:fmt"

TOP_USAGE :: `mac-cli — multi-purpose macOS command-line tool

USAGE
  mac-cli <command> [args...]

COMMANDS
  clean        Clean caches, logs, junk, and unused files
  help [cmd]   Show help (optionally for a specific command)
  version      Print version

EXAMPLES
  mac-cli clean
  mac-cli clean --risky
  mac-cli clean categories
  mac-cli help clean
`

CLEAN_USAGE :: `mac-cli clean — disk cleaner for macOS

USAGE
  mac-cli clean [flags]                 Interactive scan → select → clean
  mac-cli clean <subcommand> [flags]

FLAGS (default interactive mode)
  -r, --risky            Include risky categories (downloads, iOS backups, …)
  -f, --file-picker      Force file picker for ALL supported categories
  -A, --absolute-paths   Show absolute paths instead of abbreviated
      --no-progress      Disable progress bars

SUBCOMMANDS
  uninstall              Remove apps and their associated files
  maintenance            Maintenance tasks (DNS flush, purgeable, snapshots)
  categories             List the 16 cleanable categories
  config                 Manage ~/.mac-cli/clean/config.json
  backup                 Manage pre-delete backups

EXAMPLES
  mac-cli clean
  mac-cli clean --risky -f
  mac-cli clean maintenance --dns
  mac-cli clean uninstall --dry-run
  mac-cli clean config --init
`

print_top_help :: proc() {
	fmt.print(TOP_USAGE)
}

print_help :: proc(topic: string) {
	switch topic {
	case "", "help":
		fmt.print(TOP_USAGE)
	case "clean":
		fmt.print(CLEAN_USAGE)
	case:
		fmt.eprintfln("mac-cli help: unknown topic %q", topic)
		fmt.eprint(TOP_USAGE)
	}
}
