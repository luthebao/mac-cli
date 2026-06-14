package clean_monitor

import "core:fmt"
import "core:strings"

import "mc:fsx"
import "mc:util"

@(private="file") BAR_WIDTH :: 18

// render builds the full dashboard frame as a single string (lines joined by
// \n). The caller positions the cursor at home and prints it each tick.
render :: proc(s: Snapshot, allocator := context.allocator) -> string {
	b := strings.builder_make(context.temp_allocator)

	// ── header ───────────────────────────────────────────────────────────
	dot := health_dot(s.health)
	fmt.sbprintf(&b, "%s   %s %s   %s\n",
		util.bold("mac-cli monitor"),
		dot,
		util.bold(fmt.tprintf("Health %d", s.health)),
		util.dim(spec_line(s), context.temp_allocator))
	fmt.sbprintf(&b, "%s\n", strings.repeat("─", 56, context.temp_allocator))

	// ── CPU ──────────────────────────────────────────────────────────────
	cores := fmt.tprintf("%d cores", s.ncpu)
	if s.p_cores > 0 && s.e_cores > 0 {
		cores = fmt.tprintf("%d cores · %dP+%dE", s.ncpu, s.p_cores, s.e_cores)
	}
	fmt.sbprintf(&b, "%s %s %s   %s   %s\n",
		"⚙ CPU    ",
		usage_bar(s.cpu_usage / 100),
		pct(s.cpu_usage),
		util.dim(fmt.tprintf("load %.2f / %.2f / %.2f", s.load1, s.load5, s.load15), context.temp_allocator),
		util.dim(cores, context.temp_allocator))

	// ── Memory ───────────────────────────────────────────────────────────
	fmt.sbprintf(&b, "%s %s %s   %s\n",
		"▦ Memory ",
		usage_bar(s.mem_used_pct / 100),
		pct(s.mem_used_pct),
		util.dim(fmt.tprintf("%s / %s",
			fsx.format_size(s.mem_used, context.temp_allocator),
			fsx.format_size(s.mem_total, context.temp_allocator)), context.temp_allocator))

	// ── Disk ─────────────────────────────────────────────────────────────
	fmt.sbprintf(&b, "%s %s %s   %s\n",
		"▤ Disk   ",
		usage_bar(s.disk_used_pct / 100),
		pct(s.disk_used_pct),
		util.dim(fmt.tprintf("%s free of %s  (%s)",
			fsx.format_size(s.disk_free, context.temp_allocator),
			fsx.format_size(s.disk_total, context.temp_allocator),
			s.disk_mount), context.temp_allocator))

	// ── Network ──────────────────────────────────────────────────────────
	fmt.sbprintf(&b, "%s %s   %s\n",
		"⇅ Network",
		fmt.tprintf("%s %s", util.green("↓", context.temp_allocator), rate(s.net_rx_rate)),
		fmt.tprintf("%s %s", util.cyan("↑", context.temp_allocator), rate(s.net_tx_rate)))

	// ── Power ────────────────────────────────────────────────────────────
	if s.battery_pct >= 0 {
		fmt.sbprintf(&b, "%s %s %s   %s\n",
			"⚡ Power  ",
			usage_bar(f64(s.battery_pct) / 100, true),
			pct(f64(s.battery_pct)),
			util.dim(s.battery_state, context.temp_allocator))
	} else {
		fmt.sbprintf(&b, "%s %s\n", "⚡ Power  ", util.dim("AC Power · no internal battery", context.temp_allocator))
	}

	// ── footer ───────────────────────────────────────────────────────────
	fmt.sbprintf(&b, "%s\n", strings.repeat("─", 56, context.temp_allocator))
	fmt.sbprintf(&b, "%s\n",
		util.dim(fmt.tprintf("uptime %s · refreshing every 1s · press q to quit", fmt_uptime(s.uptime_secs)), context.temp_allocator))

	return strings.clone(strings.to_string(b), allocator)
}

@(private="file")
spec_line :: proc(s: Snapshot) -> string {
	gb := s.mem_total / (1024 * 1024 * 1024)
	return fmt.tprintf("%s · %d GB · macOS %s", s.chip, gb, s.os_version)
}

// pct / rate right-align via a %s wrapper because Odin's float width specifier
// zero-pads (e.g. %5.1f of 8.7 → "008.7"); padding the formatted string with
// %Ns gives the leading SPACES we actually want.
@(private="file")
pct :: proc(v: f64) -> string {
	return fmt.tprintf("%6s", fmt.tprintf("%.1f%%", v))
}

@(private="file")
rate :: proc(mbs: f64) -> string {
	return fmt.tprintf("%7s MB/s", fmt.tprintf("%.2f", mbs))
}

// usage_bar renders a severity-colored bar. For usage metrics (default) a high
// fill is bad → green→yellow→red. Set `inverted` for battery, where a high
// fill is good (always green-ish/cyan).
@(private="file")
usage_bar :: proc(frac: f64, inverted := false) -> string {
	f := frac
	if f < 0 { f = 0 }
	if f > 1 { f = 1 }
	filled := int(f * f64(BAR_WIDTH) + 0.5)
	if filled > BAR_WIDTH { filled = BAR_WIDTH }

	full := strings.repeat("█", filled, context.temp_allocator)
	rest := strings.repeat("░", BAR_WIDTH - filled, context.temp_allocator)

	colored: string
	if inverted {
		colored = util.cyan(full, context.temp_allocator)
	} else {
		switch {
		case f >= 0.9: colored = util.red(full, context.temp_allocator)
		case f >= 0.7: colored = util.yellow(full, context.temp_allocator)
		case:          colored = util.green(full, context.temp_allocator)
		}
	}
	return strings.concatenate({colored, util.dim(rest, context.temp_allocator)}, context.temp_allocator)
}

@(private="file")
health_dot :: proc(score: int) -> string {
	switch {
	case score >= 80: return util.green("●")
	case score >= 50: return util.yellow("●")
	case:             return util.red("●")
	}
}

@(private="file")
fmt_uptime :: proc(secs: i64) -> string {
	if secs <= 0 {
		return "—"
	}
	d := secs / 86400
	h := (secs % 86400) / 3600
	m := (secs % 3600) / 60
	if d > 0 {
		return fmt.tprintf("%dd %dh %dm", d, h, m)
	}
	if h > 0 {
		return fmt.tprintf("%dh %dm", h, m)
	}
	return fmt.tprintf("%dm", m)
}
