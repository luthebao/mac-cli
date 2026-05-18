package clop

import "core:fmt"
import "core:strings"

import tui "mc:clean/tui"
import "mc:sysx"
import "mc:util"

// brew_present returns true if `brew` is on $PATH. We don't bundle a brew
// installer — that needs sudo and downloads ~500 MB, way beyond the scope
// of "auto-install a CLI dependency."
brew_present :: proc() -> bool {
	r := sysx.run_capture({"/usr/bin/which", "brew"}, context.temp_allocator)
	return r.ok && r.stdout != ""
}

// prompt_install_missing prompts once for a batch of missing tools and runs
// a single `brew install A B C ...` call on confirmation. Returns true if
// every tool ended up present after the attempt (or already was), false
// otherwise.
//
// In non-TTY contexts, tui.confirm returns the default (we pass false), so
// scripts and CI get the brew-hint behaviour without a hang.
prompt_install_missing :: proc(missing: []Tool) -> bool {
	if len(missing) == 0 {
		return true
	}

	// brew install requires brew. If brew is absent we can't help — point
	// the user at the canonical installer and bail.
	if !brew_present() {
		fmt.eprintln(util.yellow(
			"mac-cli clop: Homebrew not found.",
			context.temp_allocator,
		))
		fmt.eprintln("  Install brew first: https://brew.sh")
		fmt.eprintln("  Then re-run mac-cli clop.")
		return false
	}

	// Build the human list and the brew arg vector in one pass.
	pkg_list := make([dynamic]string, 0, len(missing), context.temp_allocator)
	for t in missing {
		append(&pkg_list, t.brew_pkg)
	}
	pkgs_str := strings.join(pkg_list[:], " ", context.temp_allocator)

	fmt.println(util.yellow(
		fmt.tprintf("mac-cli clop: missing tool%s: %s",
			"s" if len(missing) > 1 else "",
			pkgs_str),
		context.temp_allocator,
	))
	question := fmt.tprintf("Install via `brew install %s`?", pkgs_str)
	if !tui.confirm(question, false) {
		fmt.eprintln(util.dim(
			fmt.tprintf("  declined. Run manually: brew install %s", pkgs_str),
			context.temp_allocator,
		))
		return false
	}

	// brew prints its own progress; we don't capture and re-emit because
	// download/build output is too noisy to buffer cleanly. The trade-off
	// is that mac-cli appears to hang during the install — but brew on a
	// warm cache is usually fast (~5-30s per small tool). For ffmpeg the
	// first install can take a minute; that's a brew property, not ours.
	fmt.println(util.dim(
		fmt.tprintf("  running: brew install %s", pkgs_str),
		context.temp_allocator,
	))
	args := make([dynamic]string, 0, len(missing) + 2, context.temp_allocator)
	append(&args, "brew", "install")
	for t in missing {
		append(&args, t.brew_pkg)
	}
	r := sysx.run(args[:], context.temp_allocator)
	if !r.ok {
		fmt.eprintln(util.yellow("  brew install failed:", context.temp_allocator))
		// stderr tail — brew puts the most useful line near the end.
		tail := tail_lines(r.stderr, 5)
		if tail != "" {
			fmt.eprintln(tail)
		}
		return false
	}

	// Re-probe: a successful brew install can still leave the bin off
	// $PATH (rare — usually only if the user's shell didn't `brew shellenv`
	// before mac-cli launched). If so, the second which still fails and
	// we report it cleanly.
	all_present := true
	for t in missing {
		if !tool_present(t) {
			fmt.eprintln(util.yellow(
				fmt.tprintf("  %q still not on $PATH after install; check `brew shellenv`", t.bin),
				context.temp_allocator,
			))
			all_present = false
		}
	}
	if all_present {
		fmt.println(util.green("  installed ✓", context.temp_allocator))
	}
	return all_present
}

@(private)
tail_lines :: proc(s: string, n: int) -> string {
	lines := strings.split_lines(s, context.temp_allocator)
	if len(lines) <= n {
		return s
	}
	return strings.join(lines[len(lines)-n:], "\n", context.temp_allocator)
}
