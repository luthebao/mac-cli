package clop

import "core:fmt"
import "core:strconv"
import "core:strings"

import "mc:cli"
import "mc:util"

// Op is the verb the user picked. The four verb flags are mutually
// exclusive — pick one, or get a usage error.
Op :: enum {
	None,
	Optimise,
	Downscale,
	Convert,
	StripExif,
}

// Options bundles parsed flags into a single value passed to op handlers.
Options :: struct {
	op:          Op,
	target_path: string, // file or directory
	factor:      f64,    // -d 0.5 or 50% → 0.5; only set when op == Downscale
	to_format:   string, // -c webp|heic|avif; only set when op == Convert
	aggressive:  bool,   // -a
	recursive:   bool,   // -r
	keep_orig:   bool,   // -k
}

// dispatch routes `mac-cli clop ...`. See clop_help for the surface.
//
// Two entry shapes:
//   * with args  → parse flags + positional, run the requested op
//   * no args    → enter the interactive TUI (run_interactive)
//
// The TUI also fires when invoked from the top-level menu picker (which
// passes an empty arg slice), so the user-facing flow is the same whether
// they typed `mac-cli clop` or selected "clop" from `mac-cli`'s menu.
dispatch :: proc(args: []string) -> int {
	if len(args) == 0 {
		return run_interactive()
	}

	spec := []cli.Flag{
		{name = "optimise",   short = "o", takes_value = false},
		{name = "downscale",  short = "d", takes_value = true},
		{name = "convert",    short = "c", takes_value = true},
		{name = "stripexif",  short = "s", takes_value = false},
		{name = "aggressive", short = "a", takes_value = false},
		{name = "recursive",  short = "r", takes_value = false},
		{name = "keep",       short = "k", takes_value = false},
		{name = "help",       short = "h", takes_value = false},
	}
	p := cli.parse(args, spec)

	if cli.bool_flag(p, "help") {
		print_help()
		return 0
	}

	opts, perr := build_options(p)
	if perr != "" {
		fmt.eprintfln("mac-cli clop: %s", perr)
		print_help()
		return 2
	}

	switch opts.op {
	case .Optimise:  return run_optimise(opts)
	case .Downscale: return run_downscale(opts)
	case .Convert:   return run_convert(opts)
	case .StripExif: return run_stripexif(opts)
	case .None:      return 2 // unreachable: build_options enforces non-None
	}
	return 0
}

// build_options collapses ParsedFlags into a validated Options. Returns a
// non-empty error string on failure (caller prints + exits).
@(private)
build_options :: proc(p: cli.ParsedFlags) -> (opts: Options, err: string) {
	verb_count := 0
	if cli.bool_flag(p, "optimise")  { opts.op = .Optimise;  verb_count += 1 }
	if cli.string_flag(p, "downscale") != "" {
		opts.op = .Downscale
		raw := cli.string_flag(p, "downscale")
		f, ok := parse_factor(raw)
		if !ok {
			return opts, fmt.tprintf("invalid -d factor %q (expected e.g. 0.5 or 50%%)", raw)
		}
		opts.factor = f
		verb_count += 1
	}
	if cli.string_flag(p, "convert") != "" {
		opts.op = .Convert
		fmt_str := strings.to_lower(cli.string_flag(p, "convert"), context.temp_allocator)
		switch fmt_str {
		case "webp", "heic", "avif":
			opts.to_format = strings.clone(fmt_str)
		case:
			return opts, fmt.tprintf("invalid -c format %q (expected webp|heic|avif)", fmt_str)
		}
		verb_count += 1
	}
	if cli.bool_flag(p, "stripexif") { opts.op = .StripExif; verb_count += 1 }

	if verb_count == 0 {
		return opts, "missing operation flag (one of -o, -d, -c, -s)"
	}
	if verb_count > 1 {
		return opts, "pick exactly one operation flag (-o, -d, -c, or -s)"
	}
	if len(p.positional) == 0 {
		return opts, "missing <path> argument"
	}
	if len(p.positional) > 1 {
		return opts, fmt.tprintf("too many positional args (%d); expected one <path>", len(p.positional))
	}

	opts.target_path = p.positional[0]
	opts.aggressive  = cli.bool_flag(p, "aggressive")
	opts.recursive   = cli.bool_flag(p, "recursive")
	opts.keep_orig   = cli.bool_flag(p, "keep")
	return
}

// parse_factor accepts "0.5", ".5", or "50%". Rejects values outside (0, 1).
// Returning a factor in (0,1] mirrors Clop's `toFraction` semantics.
@(private)
parse_factor :: proc(s: string) -> (f64, bool) {
	if s == "" { return 0, false }
	v: f64
	ok: bool
	if strings.has_suffix(s, "%") {
		pct: f64
		pct, ok = strconv.parse_f64(s[:len(s)-1])
		if !ok { return 0, false }
		v = pct / 100.0
	} else {
		v, ok = strconv.parse_f64(s)
		if !ok { return 0, false }
	}
	if v <= 0 || v > 1 { return 0, false }
	return v, true
}

// report_summary prints a final line after a batch run.
report_summary :: proc(processed, skipped, failed: int) {
	parts := make([dynamic]string, 0, 4, context.temp_allocator)
	if processed > 0 {
		append(&parts, util.green(fmt.tprintf("%d processed", processed), context.temp_allocator))
	}
	if skipped > 0 {
		append(&parts, util.dim(fmt.tprintf("%d skipped", skipped), context.temp_allocator))
	}
	if failed > 0 {
		append(&parts, util.yellow(fmt.tprintf("%d failed", failed), context.temp_allocator))
	}
	if len(parts) == 0 {
		fmt.println(util.dim("clop: nothing to do.", context.temp_allocator))
		return
	}
	fmt.println(strings.join(parts[:], "  ", context.temp_allocator))
}

@(private)
print_help :: proc() {
	cli.print_help("clop")
}
