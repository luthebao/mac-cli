package cli

import "core:fmt"

TOP_USAGE :: `mac-cli — multi-purpose macOS command-line tool

USAGE
  mac-cli <command> [args...]

COMMANDS
  clean        Clean caches, logs, junk, and unused files
  shot         Take a screenshot (full screen or a specific app)
  update       Update mac-cli itself to the latest release
  help [cmd]   Show help (optionally for a specific command)
  version      Print version

EXAMPLES
  mac-cli clean
  mac-cli clean --risky
  mac-cli clean categories
  mac-cli shot
  mac-cli shot -s
  mac-cli shot -l
  mac-cli update
  mac-cli update --check
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

SHOT_USAGE :: `mac-cli shot — take a macOS screenshot

USAGE
  mac-cli shot              Interactive picker (type to filter, ↑↓ navigate, ⏎ select)
  mac-cli shot -s           Capture the whole screen
  mac-cli shot -l           List running GUI apps with PID and name
  mac-cli shot -p <pid>     Capture the app with the given PID

All screenshots are saved to ~/Desktop as .png files.
First run may prompt for Screen Recording permission in System Settings → Privacy.

EXAMPLES
  mac-cli shot
  mac-cli shot -s
  mac-cli shot -l
  mac-cli shot -p 1234
`

UPDATE_USAGE :: `mac-cli update — pull the latest release binary

USAGE
  mac-cli update              Check for a new release; install it if found.
  mac-cli update --check      Only report whether a newer release exists.
                              Exits non-zero when an update is available.
  mac-cli update --force      Re-run the installer even if already current.

ENVIRONMENT
  PREFIX=<dir>                Install dir for the new binary
                              (forwarded to the install script).
  VERSION=<x.y.z>             Pin a specific release instead of latest.

EXAMPLES
  mac-cli update
  mac-cli update --check
  PREFIX=$HOME/.local/bin mac-cli update
`

print_help :: proc(topic: string) {
	switch topic {
	case "", "help":
		fmt.print(TOP_USAGE)
	case "clean":
		fmt.print(CLEAN_USAGE)
	case "shot":
		fmt.print(SHOT_USAGE)
	case "update":
		fmt.print(UPDATE_USAGE)
	case:
		fmt.eprintfln("mac-cli help: unknown topic %q", topic)
		fmt.eprint(TOP_USAGE)
	}
}
