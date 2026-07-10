package clean_cmd

import "core:fmt"
import "core:time"

import "mc:cli"
import "mc:clean/monitor"
import "mc:clean/tui"

@(private="file") REFRESH_MS :: 1000

// run_monitor drives the live system dashboard: a full-screen, alt-buffer view
// that re-collects metrics and redraws once per second until the user presses
// q / Esc. Falls back to a one-shot snapshot when stdin isn't a TTY (pipes,
// CI), and supports --json for scripting.
run_monitor :: proc(args: []string) -> int {
	spec := []cli.Flag{
		{name = "help", short = "h", takes_value = false},
		{name = "json", takes_value = false},
	}
	p := cli.parse(args, spec)

	if cli.bool_flag(p, "help") {
		fmt.println(
`mac-cli clean monitor — live system dashboard

USAGE
  mac-cli clean monitor [--json]

OPTIONS
  --json   Print one snapshot as JSON and exit (for scripting)

Shows real-time CPU, memory, disk, network, and power with a health score.
Refreshes every second; press q or Esc to quit. When stdin isn't a terminal
it prints a single snapshot instead of the live view.
`)
		return 0
	}

	if cli.bool_flag(p, "json") {
		print_json(one_shot_snapshot())
		return 0
	}

	// Live view requires raw-mode stdin. If we can't get it (piped / non-TTY),
	// degrade to a single rendered snapshot so the command still does something.
	if !tui.enter_raw() {
		fmt.print(monitor.render(one_shot_snapshot(), context.temp_allocator))
		return 0
	}
	tui.enter_alt()
	tui.hide_cursor()
	defer tui.restore()
	defer tui.leave_alt()
	defer tui.show_cursor()

	prev: monitor.Snapshot
	have_prev := false
	prev_tick := time.tick_now()

	for {
		// Reclaim the previous frame's scratch allocations. Safe because we
		// only read numeric fields from `prev` (network counters), never its
		// strings, after this point.
		free_all(context.temp_allocator)

		now := time.tick_now()
		elapsed := time.duration_seconds(time.tick_diff(prev_tick, now))

		s := monitor.collect(context.temp_allocator)
		if have_prev {
			monitor.rates_from(&s, prev, elapsed)
		}
		s.health = monitor.compute_health_score(s)

		tui.home_clear()
		fmt.print(monitor.render(s, context.temp_allocator))
		tui.clear_down()

		prev = s
		prev_tick = now
		have_prev = true

		// Drain input until the refresh deadline. Ignored keys must NOT fall
		// through to an early re-collect: a few-ms elapsed would divide the
		// network byte delta by a near-zero denominator and spike the rate
		// display (and spawn a whole extra round of subprocesses per press).
		poll_start := time.tick_now()
		remaining: i32 = REFRESH_MS
		for remaining > 0 {
			k, ok := tui.poll_key(remaining)
			if !ok {
				break // timeout → redraw
			}
			#partial switch k {
			case .Esc, .Ctrl_C, .Ctrl_D:
				return 0
			case .Char:
				if tui.last_char() == 'q' || tui.last_char() == 'Q' {
					return 0
				}
			}
			waited := i32(time.duration_milliseconds(time.tick_diff(poll_start, time.tick_now())))
			remaining = REFRESH_MS - waited
		}
	}
}

// one_shot_snapshot collects a snapshot for the --json / non-TTY paths.
// Network rates only exist as the diff of two samples, so it takes a second
// reading ~500ms after the first — a single sample would structurally report
// 0 B/s regardless of actual traffic.
@(private="file")
one_shot_snapshot :: proc() -> monitor.Snapshot {
	prev := monitor.collect(context.temp_allocator)
	t0 := time.tick_now()
	time.sleep(500 * time.Millisecond)
	s := monitor.collect(context.temp_allocator)
	elapsed := time.duration_seconds(time.tick_diff(t0, time.tick_now()))
	monitor.rates_from(&s, prev, elapsed)
	s.health = monitor.compute_health_score(s)
	return s
}

// print_json emits a single snapshot as JSON for `--json` / piped use. Written
// by hand (no encoding/json) to keep the dependency surface minimal, matching
// the rest of the project.
@(private="file")
print_json :: proc(s: monitor.Snapshot) {
	fmt.println("{")
	fmt.printfln(`  "host": %q,`, s.host)
	fmt.printfln(`  "chip": %q,`, s.chip)
	fmt.printfln(`  "os_version": %q,`, s.os_version)
	fmt.printfln(`  "health_score": %d,`, s.health)
	fmt.printfln(`  "cpu": {{ "usage": %.1f, "load1": %.2f, "load5": %.2f, "load15": %.2f, "ncpu": %d }},`,
		s.cpu_usage, s.load1, s.load5, s.load15, s.ncpu)
	fmt.printfln(`  "memory": {{ "used": %d, "total": %d, "used_percent": %.1f }},`,
		s.mem_used, s.mem_total, s.mem_used_pct)
	fmt.printfln(`  "disk": {{ "used": %d, "total": %d, "free": %d, "used_percent": %.1f, "mount": %q }},`,
		s.disk_used, s.disk_total, s.disk_free, s.disk_used_pct, s.disk_mount)
	fmt.printfln(`  "network": {{ "rx_mbs": %.2f, "tx_mbs": %.2f }},`, s.net_rx_rate, s.net_tx_rate)
	fmt.printfln(`  "battery": {{ "percent": %d, "state": %q }},`, s.battery_pct, s.battery_state)
	fmt.printfln(`  "uptime_secs": %d`, s.uptime_secs)
	fmt.println("}")
}
