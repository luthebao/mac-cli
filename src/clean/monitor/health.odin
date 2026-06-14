package clean_monitor

// compute_health_score condenses the whole dashboard into one 0–100 number,
// the way mole's status header does. It's deliberately a small, isolated
// policy function: the "right" weighting is a judgment call (Is a full disk
// worse than a pegged CPU? Should a draining battery cost points?), so this is
// the natural place to encode YOUR priorities.
//
// Default policy: start at a perfect 100 and subtract escalating penalties as
// each subsystem comes under pressure. CPU spikes are transient (small
// penalty); a nearly-full disk is a real, sticky problem (large penalty).
//
//   ── Tunable seam ──────────────────────────────────────────────────────────
//   Adjust the thresholds/penalties below to match how YOU think about Mac
//   health. Ideas: weight memory pressure higher on a RAM-starved machine,
//   add a penalty when battery is low while discharging, or factor in load
//   average relative to core count (load1 > ncpu ⇒ oversubscribed).
//   ──────────────────────────────────────────────────────────────────────────
compute_health_score :: proc(s: Snapshot) -> int {
	score := 100

	// CPU — transient, so penalties stay modest.
	switch {
	case s.cpu_usage > 90: score -= 20
	case s.cpu_usage > 75: score -= 12
	case s.cpu_usage > 50: score -= 5
	}

	// Memory — sustained pressure hurts responsiveness.
	switch {
	case s.mem_used_pct > 90: score -= 25
	case s.mem_used_pct > 80: score -= 15
	case s.mem_used_pct > 65: score -= 5
	}

	// Disk — a full startup volume is the stickiest problem of the three.
	switch {
	case s.disk_used_pct > 95: score -= 30
	case s.disk_used_pct > 90: score -= 18
	case s.disk_used_pct > 80: score -= 8
	}

	if score < 0 { score = 0 }
	if score > 100 { score = 100 }
	return score
}
