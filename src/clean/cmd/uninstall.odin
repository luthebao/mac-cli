package clean_cmd

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

import "mc:cli"
import "mc:clean/tui"
import "mc:fsx"
import "mc:sysx"
import "mc:util"

// run_uninstall lists apps in /Applications, lets the user pick which to
// fully remove (app bundle + every leftover it scattered across ~/Library).
//
// "Smart" vs. a plain `rm -rf /Applications/Foo.app`: we read the app's real
// CFBundleIdentifier from its Info.plist and use it to find support files that
// don't share the app's display name (e.g. Visual Studio Code stores data
// under com.microsoft.VSCode, not "Visual Studio Code"). See build_app_plan.
run_uninstall :: proc(args: []string) -> int {
	spec := []cli.Flag{
		{name = "yes",     short = "y", takes_value = false},
		{name = "dry-run", short = "d", takes_value = false},
		{name = "help",    short = "h", takes_value = false},
	}
	p := cli.parse(args, spec)

	if cli.bool_flag(p, "help") {
		fmt.println(
`mac-cli clean uninstall — remove apps and their leftovers

USAGE
  mac-cli clean uninstall [--yes] [--dry-run]

OPTIONS
  --yes      Skip confirmation prompts
  --dry-run  Show what would be removed; don't actually remove

Reads each app's bundle identifier and sweeps Application Support, Caches,
Containers, Group Containers, Preferences, Logs, Saved State, WebKit,
HTTPStorages, Cookies, and LaunchAgents for matching leftovers.
`)
		return 0
	}

	dry_run := cli.bool_flag(p, "dry-run")
	yes     := cli.bool_flag(p, "yes")

	// Build app list from /Applications.
	apps, err := os.read_directory_by_path("/Applications", -1, context.temp_allocator)
	if err != nil {
		fmt.eprintln("uninstall: cannot read /Applications:", err)
		return 1
	}

	rows := make([dynamic]tui.CheckboxItem, 0, len(apps), context.temp_allocator)
	app_paths := make([dynamic]string, 0, len(apps), context.temp_allocator)
	for a in apps {
		if !strings.has_suffix(a.name, ".app") {
			continue
		}
		size, _ := fsx.dir_size(a.fullpath)
		// Age label: an app whose bundle hasn't been touched in 6 months is a
		// strong "you probably forgot about this" signal — surfaced as a hint
		// so the riskier (old, large) apps stand out in the picker.
		age := app_age_label(a.modification_time)
		hint := fsx.format_size(size, context.temp_allocator)
		if age != "" {
			hint = fmt.aprintf("%s | %s", hint, age, allocator = context.temp_allocator)
		}
		append(&rows, tui.CheckboxItem{
			label = strings.trim_suffix(a.name, ".app"),
			hint  = hint,
		})
		append(&app_paths, strings.clone(a.fullpath, context.temp_allocator))
	}

	if len(rows) == 0 {
		fmt.println("No applications found in /Applications.")
		return 0
	}

	result, _ := tui.checkbox("Select apps to uninstall", rows[:])
	if result != .Submitted {
		fmt.println(util.dim("Cancelled."))
		return 0
	}

	// Build the deletion plan for each selected app: bundle + leftovers.
	picked := 0
	plans := make([]AppPlan, len(rows), context.temp_allocator)
	for row, i in rows {
		if !row.selected {
			continue
		}
		picked += 1
		plans[i] = build_app_plan(app_paths[i])
	}
	if picked == 0 {
		fmt.println(util.dim("Nothing selected."))
		return 0
	}

	// Preview / confirm.
	fmt.println()
	fmt.println(util.bold("Will remove:"))
	total: i64 = 0
	for row, i in rows {
		if !row.selected {
			continue
		}
		bid := plans[i].bundle_id
		if bid == "" { bid = "—" }
		fmt.printfln("  %s  %s", row.label, util.dim(bid, context.temp_allocator))
		for path in plans[i].paths {
			size, _ := fsx.dir_size(path)
			total += size
			fmt.printfln("    %s  %s", fsx.format_size(size, context.temp_allocator), fsx.abbreviate(path, context.temp_allocator))
		}
		fmt.printfln("    %s", util.dim(fmt.aprintf("%d items across %d locations", len(plans[i].paths), plans[i].location_count, allocator = context.temp_allocator), context.temp_allocator))
	}
	fmt.println()
	fmt.printfln("Total: %s", fsx.format_size(total, context.temp_allocator))

	if !yes {
		ok := tui.confirm("Proceed?", false)
		if !ok {
			fmt.println(util.dim("Cancelled."))
			return 0
		}
	}

	if dry_run {
		fmt.println(util.dim("--dry-run: no changes made."))
		return 0
	}

	for row, i in rows {
		if !row.selected {
			continue
		}
		for path in plans[i].paths {
			// fsx.safe_delete refuses /Applications/* (in DANGER_PATHS),
			// so we have to fall back to direct os.remove_all for app
			// bundles. Leftover support-files paths under ~/Library
			// pass through safe_delete normally.
			if strings.has_prefix(path, "/Applications/") {
				_ = os.remove_all(path)
			} else {
				_, _ = fsx.safe_delete(path)
			}
		}
	}
	fmt.println(util.green("✓ Uninstall complete"))
	return 0
}

AppPlan :: struct {
	app_path:       string,
	bundle_id:      string,
	paths:          []string, // app bundle + every matched leftover
	location_count: int,      // distinct parent directories touched
}

// LEFTOVER_DIRS are the ~/Library subdirectories an app commonly scatters data
// into. We list each one's direct children and keep the entries that match the
// app (see leftover_matches). Order is roughly biggest-payoff first.
@(private="file")
LEFTOVER_DIRS := [?]string{
	"Library/Application Support",
	"Library/Caches",
	"Library/Containers",
	"Library/Group Containers",
	"Library/HTTPStorages",
	"Library/WebKit",
	"Library/Saved Application State",
	"Library/Logs",
	"Library/Preferences",
	"Library/Cookies",
	"Library/LaunchAgents",
}

@(private)
build_app_plan :: proc(app_path: string) -> AppPlan {
	// Derive the display name from the bundle path (best-effort).
	base := app_path
	if i := strings.last_index(app_path, "/"); i >= 0 {
		base = app_path[i+1:]
	}
	name := strings.trim_suffix(base, ".app")

	bundle_id := read_bundle_id(app_path)

	candidates := make([dynamic]string, 0, 16, context.temp_allocator)
	append(&candidates, strings.clone(app_path, context.temp_allocator))

	// Count distinct parent directories that actually contributed a leftover —
	// drives the "N items across M locations" line in the preview.
	locations := 1 // the /Applications bundle itself

	home := fsx.home(context.temp_allocator)
	for rel in LEFTOVER_DIRS {
		dir := strings.concatenate({home, "/", rel}, context.temp_allocator)
		entries, derr := os.read_directory_by_path(dir, -1, context.temp_allocator)
		if derr != nil {
			continue
		}
		hit := false
		for e in entries {
			if leftover_matches(e.name, name, bundle_id) {
				append(&candidates, strings.clone(e.fullpath, context.temp_allocator))
				hit = true
			}
		}
		if hit {
			locations += 1
		}
	}

	return AppPlan{
		app_path       = strings.clone(app_path, context.temp_allocator),
		bundle_id      = bundle_id,
		paths          = candidates[:],
		location_count = locations,
	}
}

// read_bundle_id pulls CFBundleIdentifier from the app's Info.plist via
// `defaults read`. Returns "" when the key is absent or the app is malformed —
// callers then fall back to name-only matching.
@(private="file")
read_bundle_id :: proc(app_path: string) -> string {
	// `defaults read` wants the plist path WITHOUT the .plist extension.
	info := strings.concatenate({app_path, "/Contents/Info"}, context.temp_allocator)
	r := sysx.run_capture({"defaults", "read", info, "CFBundleIdentifier"}, context.temp_allocator)
	if !r.ok {
		return ""
	}
	id := strings.trim_space(r.stdout)
	// A real bundle id always contains a dot (reverse-DNS). Guard against
	// `defaults` echoing an error onto stdout in edge cases.
	if id == "" || !strings.contains(id, ".") {
		return ""
	}
	return strings.clone(id, context.temp_allocator)
}

// leftover_matches decides whether a ~/Library entry belongs to the app being
// uninstalled. This is the safety-critical heuristic: too loose and we delete
// an unrelated app's data; too strict and we leave gigabytes of orphans.
//
// Strategy (high-confidence → low-confidence):
//   1. Bundle-id anchored — `entry` IS the bundle id, is a child namespace of
//      it (`com.foo.bar.helper`), a plist named after it (`com.foo.bar.plist`),
//      or embeds it (Group Containers use `<TEAMID>.com.foo.bar`). Reverse-DNS
//      ids are near-unique, so this is safe to match generously.
//   2. Exact display-name — only an EXACT, case-insensitive name equality.
//      We deliberately avoid name *prefix* matching: "Code" must not sweep
//      "CodeRunner". A bare name match is the weakest signal, so we keep it tight.
//
// Package-visible (not file-private) so uninstall_test.odin can pin the
// false-positive boundaries — the safety-critical property of this function.
@(private)
leftover_matches :: proc(entry_name, app_name, bundle_id: string) -> bool {
	entry := strings.to_lower(entry_name, context.temp_allocator)

	if bundle_id != "" {
		bid := strings.to_lower(bundle_id, context.temp_allocator)
		if entry == bid { return true }
		if strings.has_prefix(entry, strings.concatenate({bid, "."}, context.temp_allocator)) { return true }
		if strings.contains(entry, bid) { return true }
	}

	app := strings.to_lower(app_name, context.temp_allocator)
	// Exact name, or exact name + a known single-file suffix.
	if entry == app { return true }
	if entry == strings.concatenate({app, ".plist"}, context.temp_allocator) { return true }
	if entry == strings.concatenate({app, ".savedstate"}, context.temp_allocator) { return true }

	return false
}

// app_age_label returns "Old" for apps untouched for >180 days, "" otherwise.
// Used only as a soft hint in the picker — never gates deletion.
@(private="file")
app_age_label :: proc(mtime: time.Time) -> string {
	age := time.since(mtime)
	days := time.duration_hours(age) / 24
	if days > 180 {
		return "Old"
	}
	return ""
}
