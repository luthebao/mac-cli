package update

import "core:c/libc"
import "core:fmt"
import "core:strings"

import "mc:cli"
import "mc:sysx"

REPO        :: "luthebao/mac-cli"
INSTALL_URL :: "https://raw.githubusercontent.com/luthebao/mac-cli/main/install.sh"

// dispatch routes `mac-cli update <args...>`.
//   install    check + install if a newer release is available (default)
//   --check    only report; non-zero exit if an update is available
//   --force    run the installer even when already on the latest tag
//   (none)     open the update command menu (cli.pick_at)
//
// "install" is the menu sentinel for the default flow; it's stripped before
// flag parsing so it doesn't collide with the parser's positional handling.
dispatch :: proc(args: []string, current_version: string) -> int {
	args := args
	if len(args) == 0 {
		chosen, ok := cli.pick_at("update")
		if !ok { return 0 }
		return dispatch(chosen, current_version)
	}

	if args[0] == "install" {
		args = args[1:]
	}

	spec := []cli.Flag{
		{name = "check", short = "c", takes_value = false},
		{name = "force", short = "f", takes_value = false},
		{name = "help",  short = "h", takes_value = false},
	}
	p := cli.parse(args, spec)

	if cli.bool_flag(p, "help") {
		print_update_help()
		return 0
	}

	fmt.println("mac-cli update: resolving latest release...")
	latest, ok := resolve_latest_version()
	if !ok {
		fmt.eprintln("mac-cli update: could not determine latest version")
		fmt.eprintln("  (the repository may not have any published releases yet)")
		return 1
	}

	check_only := cli.bool_flag(p, "check")
	force      := cli.bool_flag(p, "force")

	if latest == current_version && !force {
		fmt.printfln("Already on the latest version (%s)", current_version)
		return 0
	}

	if check_only {
		fmt.printfln("Update available: %s -> %s", current_version, latest)
		fmt.println("Run `mac-cli update` to install.")
		// Non-zero so this is scriptable: `mac-cli update --check || …`
		return 1
	}

	fmt.printfln("Updating mac-cli %s -> %s", current_version, latest)
	fmt.printfln("Running: curl -fsSL %s | bash", INSTALL_URL)

	shell_cmd := fmt.tprintf("curl -fsSL %s | bash", INSTALL_URL)
	cstr := strings.clone_to_cstring(shell_cmd, context.temp_allocator)
	rc := libc.system(cstr)
	if rc != 0 {
		fmt.eprintfln("mac-cli update: installer exited with status %d", rc)
		return 1
	}
	return 0
}

// resolve_latest_version mirrors install.sh: follow the redirect from
// https://github.com/<repo>/releases/latest and parse the trailing /tag/vX.Y.Z.
// Returns ("0.2.0", true) on success. Returns ("", false) if no release exists
// (the redirect lands on /releases with no /tag/ segment).
resolve_latest_version :: proc() -> (string, bool) {
	url := fmt.tprintf("https://github.com/%s/releases/latest", REPO)
	r := sysx.run_capture({
		"curl", "-fsSLI",
		"-o", "/dev/null",
		"-w", "%{url_effective}",
		url,
	}, context.temp_allocator)
	if !r.ok {
		return "", false
	}

	idx := strings.last_index(r.stdout, "/tag/")
	if idx < 0 {
		return "", false
	}
	tag := strings.trim(r.stdout[idx+len("/tag/"):], " \r\n\t/")
	tag = strings.trim_prefix(tag, "v")
	if tag == "" {
		return "", false
	}
	return strings.clone(tag), true
}

print_update_help :: proc() {
	fmt.print(
`mac-cli update — pull the latest release binary

USAGE
  mac-cli update              Check for a new release; install it if found.
  mac-cli update --check      Only report whether a newer release exists.
                              Exits non-zero when an update is available.
  mac-cli update --force      Re-run the installer even if already current.

ENVIRONMENT
  PREFIX=<dir>                Install dir for the new binary
                              (forwarded to the install script).
  VERSION=<x.y.z>             Pin a specific release instead of latest.

The installer is fetched from:
  ` + INSTALL_URL + `
`)
}
