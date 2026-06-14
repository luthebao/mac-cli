// Package clean_monitor collects and renders a live system dashboard:
// CPU, memory, disk, network, and power. Every metric is gathered by shelling
// out to a native macOS tool through mc:sysx — no third-party dependency, in
// keeping with the project's single-binary, subprocess-discipline rules.
package clean_monitor

import "base:runtime"
import "core:strconv"
import "core:strings"
import "core:time"

import "mc:sysx"

// Snapshot is one moment of system state. Network *rates* aren't part of a
// single reading — they're derived by diffing two snapshots over time (see
// rates_from), so collect() fills the cumulative byte counters and the caller
// computes net_rx_rate / net_tx_rate.
Snapshot :: struct {
	host:       string,
	chip:       string,
	os_version: string,

	cpu_usage:    f64, // 0..100, busy = 100 - idle
	load1:        f64,
	load5:        f64,
	load15:       f64,
	ncpu:         int,
	p_cores:      int,
	e_cores:      int,

	mem_total:    i64,
	mem_used:     i64,
	mem_used_pct: f64,

	disk_total:    i64,
	disk_used:     i64,
	disk_free:     i64,
	disk_used_pct: f64,
	disk_mount:    string,

	net_rx_bytes: i64, // cumulative since boot
	net_tx_bytes: i64,
	net_rx_rate:  f64, // MB/s, derived
	net_tx_rate:  f64,

	battery_pct:   int,    // -1 when no internal battery (desktop)
	battery_state: string, // "charged" / "charging" / "discharging" / "AC Power"

	uptime_secs: i64,
	health:      int,
}

// collect gathers a full snapshot. Cheap enough (~7 short subprocesses) to run
// once per second. Network rates are left at 0 here; fill them with rates_from.
collect :: proc(allocator := context.temp_allocator) -> Snapshot {
	s: Snapshot

	s.host       = sysctl_str("kern.hostname", allocator)
	s.chip       = sysctl_str("machdep.cpu.brand_string", allocator)
	s.os_version = strings.clone(strings.trim_space(sysx.run_capture({"sw_vers", "-productVersion"}, context.temp_allocator).stdout), allocator)

	collect_cpu(&s)
	collect_memory(&s)
	collect_disk(&s, allocator)
	collect_network(&s)
	collect_power(&s, allocator)

	// kern.boottime has no addressable .sec sub-OID; parse the struct text:
	// "{ sec = 1781353672, usec = ... } Sat Jun 13 ...". Search for " sec = "
	// (leading space) so we don't match the "usec = " field.
	if bt := sysctl_str("kern.boottime", context.temp_allocator); bt != "" {
		if idx := strings.index(bt, " sec = "); idx >= 0 {
			rest := bt[idx + 7:]
			end := 0
			for end < len(rest) && rest[end] >= '0' && rest[end] <= '9' {
				end += 1
			}
			boot, _ := strconv.parse_i64(rest[:end])
			now := time.time_to_unix(time.now())
			if boot > 0 && now > boot {
				s.uptime_secs = now - boot
			}
		}
	}
	return s
}

// rates_from fills cur's network rates by diffing against a previous snapshot
// taken `elapsed` seconds earlier. Counter wrap / first-frame (prev all zero)
// degrade to 0 rather than producing garbage spikes.
rates_from :: proc(cur: ^Snapshot, prev: Snapshot, elapsed: f64) {
	if elapsed <= 0 || prev.net_rx_bytes == 0 && prev.net_tx_bytes == 0 {
		return
	}
	mb :: 1024.0 * 1024.0
	if cur.net_rx_bytes >= prev.net_rx_bytes {
		cur.net_rx_rate = f64(cur.net_rx_bytes - prev.net_rx_bytes) / mb / elapsed
	}
	if cur.net_tx_bytes >= prev.net_tx_bytes {
		cur.net_tx_rate = f64(cur.net_tx_bytes - prev.net_tx_bytes) / mb / elapsed
	}
}

// ── per-subsystem collectors ────────────────────────────────────────────────

@(private)
collect_cpu :: proc(s: ^Snapshot) {
	s.ncpu = int(sysctl_i64("hw.logicalcpu"))
	if s.ncpu <= 0 {
		s.ncpu = int(sysctl_i64("hw.ncpu"))
	}
	if s.ncpu <= 0 {
		s.ncpu = 1
	}
	// Apple Silicon performance/efficiency split (perflevel0 = P, 1 = E).
	s.p_cores = int(sysctl_i64("hw.perflevel0.logicalcpu"))
	s.e_cores = int(sysctl_i64("hw.perflevel1.logicalcpu"))

	// Load averages: "{ 1.23 1.05 0.98 }".
	if v := sysctl_str("vm.loadavg", context.temp_allocator); v != "" {
		body := v
		body = strings.trim(body, "{} ")
		fields := strings.fields(body, context.temp_allocator)
		if len(fields) >= 3 {
			s.load1, _  = strconv.parse_f64(fields[0])
			s.load5, _  = strconv.parse_f64(fields[1])
			s.load15, _ = strconv.parse_f64(fields[2])
		}
	}

	// Instant CPU%: sum of per-process %cpu / core count. Fast and dependency
	// free; lags slightly vs. a true sampler but fine for a 1s dashboard.
	r := sysx.run_capture({"ps", "-Aceo", "pcpu"}, context.temp_allocator)
	total: f64 = 0
	first := true
	for line in strings.split_lines_iterator(&r.stdout) {
		t := strings.trim_space(line)
		if t == "" { continue }
		if first { first = false; continue } // header (%CPU)
		v, ok := strconv.parse_f64(t)
		if ok { total += v }
	}
	usage := total / f64(s.ncpu)
	if usage < 0 { usage = 0 }
	if usage > 100 { usage = 100 }
	s.cpu_usage = usage
}

@(private)
collect_memory :: proc(s: ^Snapshot) {
	s.mem_total = sysctl_i64("hw.memsize")
	page := sysctl_i64("hw.pagesize")
	if page <= 0 { page = 4096 }

	// "Used" on macOS ≈ active + wired + compressed pages. Inactive/free are
	// reclaimable, so we exclude them — this tracks Activity Monitor closely.
	r := sysx.run_capture({"vm_stat"}, context.temp_allocator)
	active, wired, compressed: i64
	for line in strings.split_lines_iterator(&r.stdout) {
		if strings.has_prefix(line, "Pages active:") {
			active = vmstat_pages(line)
		} else if strings.has_prefix(line, "Pages wired down:") {
			wired = vmstat_pages(line)
		} else if strings.has_prefix(line, "Pages occupied by compressor:") {
			compressed = vmstat_pages(line)
		}
	}
	s.mem_used = (active + wired + compressed) * page
	if s.mem_used > s.mem_total { s.mem_used = s.mem_total }
	if s.mem_total > 0 {
		s.mem_used_pct = f64(s.mem_used) / f64(s.mem_total) * 100
	}
}

@(private)
collect_disk :: proc(s: ^Snapshot, allocator: runtime.Allocator) {
	s.disk_mount = strings.clone("/", allocator)
	r := sysx.run_capture({"df", "-k", "/"}, context.temp_allocator)
	first := true
	for line in strings.split_lines_iterator(&r.stdout) {
		if first { first = false; continue } // header
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) < 4 { continue }
		blocks, _ := strconv.parse_i64(fields[1])
		avail, _  := strconv.parse_i64(fields[3])
		// Compute used as total − available rather than trusting df's per-volume
		// "Used" column. On modern macOS "/" is a sealed system snapshot showing
		// near-zero use, while real data lives on a sibling Data volume sharing
		// the same APFS container — but `blocks`/`avail` are container-wide, so
		// total − avail captures system + data + snapshots (matches Finder).
		s.disk_total = blocks * 1024
		s.disk_free  = avail * 1024
		s.disk_used  = (blocks - avail) * 1024
		if s.disk_total > 0 {
			s.disk_used_pct = f64(s.disk_used) / f64(s.disk_total) * 100
		}
		break
	}
}

@(private)
collect_network :: proc(s: ^Snapshot) {
	// netstat -ibn prints one "<Link#n>" row per interface carrying cumulative
	// byte counters; summing only those rows avoids double-counting the
	// per-address-family rows. Skip virtual/noise interfaces. The -n
	// (numeric) flag is critical: without it netstat attempts name resolution
	// that stalls ~5s when stdout is a pipe rather than a terminal.
	r := sysx.run_capture({"netstat", "-ibn"}, context.temp_allocator)
	rx, tx: i64
	first := true
	for line in strings.split_lines_iterator(&r.stdout) {
		if first { first = false; continue } // header
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) < 10 { continue }
		if !strings.has_prefix(fields[2], "<Link") { continue }
		if is_noise_iface(fields[0]) { continue }
		ib, _ := strconv.parse_i64(fields[6])
		ob, _ := strconv.parse_i64(fields[9])
		rx += ib
		tx += ob
	}
	s.net_rx_bytes = rx
	s.net_tx_bytes = tx
}

@(private)
collect_power :: proc(s: ^Snapshot, allocator: runtime.Allocator) {
	s.battery_pct = -1
	s.battery_state = strings.clone("AC Power", allocator)

	r := sysx.run_capture({"pmset", "-g", "batt"}, context.temp_allocator)
	if !r.ok { return }

	for line in strings.split_lines_iterator(&r.stdout) {
		// Percent: the token immediately before a '%'.
		if pct := percent_before(line); pct >= 0 {
			s.battery_pct = pct
		}
		low := strings.to_lower(line, context.temp_allocator)
		switch {
		case strings.contains(low, "charged"):     s.battery_state = strings.clone("Charged", allocator)
		case strings.contains(low, "discharging"): s.battery_state = strings.clone("Battery", allocator)
		case strings.contains(low, "charging"):    s.battery_state = strings.clone("Charging", allocator)
		case strings.contains(low, "ac power"):     s.battery_state = strings.clone("AC Power", allocator)
		}
	}
}

// ── parse helpers ───────────────────────────────────────────────────────────

@(private)
sysctl_str :: proc(name: string, allocator := context.allocator) -> string {
	r := sysx.run_capture({"sysctl", "-n", name}, context.temp_allocator)
	if !r.ok { return strings.clone("", allocator) }
	return strings.clone(strings.trim_space(r.stdout), allocator)
}

@(private)
sysctl_i64 :: proc(name: string) -> i64 {
	r := sysx.run_capture({"sysctl", "-n", name}, context.temp_allocator)
	if !r.ok { return 0 }
	v, _ := strconv.parse_i64(strings.trim_space(r.stdout))
	return v
}

// vmstat_pages extracts the page count from a "Pages X: 12345." line.
@(private)
vmstat_pages :: proc(line: string) -> i64 {
	colon := strings.index_byte(line, ':')
	if colon < 0 { return 0 }
	num := strings.trim_space(line[colon + 1:])
	num = strings.trim_right(num, ".")
	v, _ := strconv.parse_i64(num)
	return v
}

// percent_before returns the integer right before a '%' in `line`, or -1.
@(private)
percent_before :: proc(line: string) -> int {
	pct := strings.index_byte(line, '%')
	if pct <= 0 { return -1 }
	// Walk back over digits.
	end := pct
	start := end
	for start > 0 && line[start - 1] >= '0' && line[start - 1] <= '9' {
		start -= 1
	}
	if start == end { return -1 }
	v, ok := strconv.parse_int(line[start:end])
	if !ok { return -1 }
	return v
}

@(private)
NOISE_IFACES := [?]string{"lo", "awdl", "llw", "utun", "bridge", "gif", "stf", "anpi", "ap", "p2p"}

@(private)
is_noise_iface :: proc(name: string) -> bool {
	for p in NOISE_IFACES {
		if strings.has_prefix(name, p) {
			return true
		}
	}
	return false
}
