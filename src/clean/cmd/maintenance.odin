package clean_cmd

import "core:fmt"

import "mc:cli"
import "mc:sysx"
import "mc:util"

run_maintenance :: proc(args: []string) -> int {
	spec := []cli.Flag{
		{name = "dns",         takes_value = false},
		{name = "purgeable",   takes_value = false},
		{name = "timemachine", takes_value = false},
		{name = "help",        short = "h", takes_value = false},
	}
	p := cli.parse(args, spec)

	if cli.bool_flag(p, "help") {
		fmt.println(
`mac-cli clean maintenance — system maintenance tasks

USAGE
  mac-cli clean maintenance --dns          Flush DNS cache (uses sudo)
  mac-cli clean maintenance --purgeable    Thin Time Machine local snapshots
  mac-cli clean maintenance --timemachine  List + delete local TM snapshots
`)
		return 0
	}

	any_run := false

	if cli.bool_flag(p, "dns") {
		any_run = true
		fmt.println(util.bold("→ Flushing DNS cache"))
		ok := sysx.run_quiet({"/usr/bin/sudo", "/usr/bin/dscacheutil", "-flushcache"})
		ok = sysx.run_quiet({"/usr/bin/sudo", "/usr/bin/killall", "-HUP", "mDNSResponder"}) && ok
		report("DNS cache flushed", ok)
	}

	if cli.bool_flag(p, "purgeable") {
		any_run = true
		fmt.println(util.bold("→ Freeing purgeable space"))
		ok := sysx.run_quiet({"/usr/bin/sudo", "/usr/bin/tmutil", "thinlocalsnapshots", "/", "999999999999", "1"})
		report("Purgeable space freed", ok)
	}

	if cli.bool_flag(p, "timemachine") {
		any_run = true
		fmt.println(util.bold("→ Listing Time Machine local snapshots"))
		r := sysx.run_capture({"/usr/bin/tmutil", "listlocalsnapshots", "/"}, context.temp_allocator)
		if !r.ok {
			fmt.println(util.yellow("  could not list snapshots"))
		} else {
			fmt.println(r.stdout)
		}
	}

	if !any_run {
		fmt.println("Pass --dns, --purgeable, or --timemachine. Run with --help for details.")
		return 1
	}
	return 0
}

@(private)
report :: proc(label: string, ok: bool) {
	if ok {
		fmt.printfln("  %s %s", util.green("✓", context.temp_allocator), label)
	} else {
		fmt.printfln("  %s %s (failed)", util.red("✗", context.temp_allocator), label)
	}
}
