package clean_cmd

import "core:fmt"
import "core:time"

import "mc:cli"
import "mc:clean/store"
import "mc:fsx"
import "mc:util"

run_backup :: proc(args: []string) -> int {
	if len(args) == 0 {
		chosen, ok := cli.pick_at("clean", "backup")
		if !ok { return 0 }
		return run_backup(chosen)
	}

	spec := []cli.Flag{
		{name = "list",  takes_value = false},
		{name = "clean", takes_value = false},
		{name = "help",  short = "h", takes_value = false},
	}
	p := cli.parse(args, spec)

	if cli.bool_flag(p, "help") {
		fmt.println(
`mac-cli clean backup — manage pre-delete backups

USAGE
  mac-cli clean backup --list    List backup sessions on disk
  mac-cli clean backup --clean   Remove sessions older than 7 days
`)
		return 0
	}

	if cli.bool_flag(p, "list") {
		entries := store.list_backups()
		if len(entries) == 0 {
			fmt.println("No backups found.")
			return 0
		}
		fmt.printfln("%s under %s", util.bold("Backups"), store.backup_root(context.temp_allocator))
		for e in entries {
			y, m, d := time.date(e.created_at)
			fmt.printfln("  %04d-%02d-%02d  %s  %s",
				y, int(m), d,
				fsx.format_size(e.size, context.temp_allocator),
				e.path)
		}
		return 0
	}

	if cli.bool_flag(p, "clean") {
		removed := store.clean_old_backups()
		fmt.printfln("Removed %d old backup session(s).", removed)
		return 0
	}

	fmt.println("Use --list to show backups or --clean to remove old ones.")
	return 0
}
