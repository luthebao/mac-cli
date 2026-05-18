package shot

import "core:fmt"
import "core:strconv"

import "mc:cli"

// dispatch routes `mac-cli shot <args...>` to the right mode:
//   -s            full-screen capture
//   -l            list running GUI apps
//   -p <pid>      capture a specific app by PID
//   interactive   type-to-filter app picker
//   (none)        open the shot command menu (cli.pick_at)
//
// "interactive" is a sentinel routed below: the menu's default leaf passes
// it so the picker can be reached without falling back to len(args)==0,
// which now means "show the menu".
dispatch :: proc(args: []string) -> int {
	if len(args) == 0 {
		chosen, ok := cli.pick_at("shot")
		if !ok { return 0 }
		return dispatch(chosen)
	}

	if args[0] == "interactive" {
		return cmd_interactive()
	}

	spec := []cli.Flag{
		{name = "screen", short = "s", takes_value = false},
		{name = "list",   short = "l", takes_value = false},
		{name = "pid",    short = "p", takes_value = true},
		{name = "help",   short = "h", takes_value = false},
	}
	p := cli.parse(args, spec)

	if cli.bool_flag(p, "help") {
		print_shot_help()
		return 0
	}

	pid_str := cli.string_flag(p, "pid", "")
	if pid_str != "" {
		pid, ok := strconv.parse_int(pid_str)
		if !ok || pid <= 0 {
			fmt.eprintfln("mac-cli shot: invalid PID %q", pid_str)
			return 2
		}
		return cmd_capture_pid(pid)
	}

	if cli.bool_flag(p, "screen") {
		return cmd_full_screen()
	}
	if cli.bool_flag(p, "list") {
		return cmd_list_apps()
	}
	return cmd_interactive()
}

print_shot_help :: proc() {
	fmt.print(
`mac-cli shot — take a macOS screenshot

USAGE
  mac-cli shot              Interactive picker (type to filter, ↑↓ navigate, ⏎ select)
  mac-cli shot -s           Capture the whole screen
  mac-cli shot -l           List running GUI apps with PID and name
  mac-cli shot -p <pid>     Capture the app with the given PID

All screenshots are saved to ~/Desktop as .png files.
First run may prompt for Screen Recording permission in System Settings.
`)
}
