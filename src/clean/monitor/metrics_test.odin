package clean_monitor

import "core:testing"

@(test)
test_vmstat_pages :: proc(t: ^testing.T) {
	testing.expect_value(t, vmstat_pages("Pages active:                              388975."), 388975)
	testing.expect_value(t, vmstat_pages("Pages wired down: 123."), 123)
	testing.expect_value(t, vmstat_pages("Pages occupied by compressor: 0."), 0)
	testing.expect_value(t, vmstat_pages("no colon here"), 0)
}

@(test)
test_percent_before :: proc(t: ^testing.T) {
	testing.expect_value(t, percent_before(" -InternalBattery-0 (id=123)\t87%; charged"), 87)
	testing.expect_value(t, percent_before("100%; charged"), 100)
	testing.expect_value(t, percent_before("Now drawing from 'AC Power'"), -1) // no percent
	testing.expect_value(t, percent_before("%"), -1)                            // bare percent sign
}

@(test)
test_is_noise_iface :: proc(t: ^testing.T) {
	testing.expect(t, !is_noise_iface("en0"), "en0 is a real interface")
	testing.expect(t, is_noise_iface("lo0"), "loopback is noise")
	testing.expect(t, is_noise_iface("utun3"), "vpn tunnel is noise")
	testing.expect(t, is_noise_iface("bridge0"), "bridge is noise")
	testing.expect(t, is_noise_iface("awdl0"), "airdrop link is noise")
}

@(test)
test_health_score :: proc(t: ^testing.T) {
	// Idle, roomy machine → perfect score.
	healthy := Snapshot{cpu_usage = 10, mem_used_pct = 40, disk_used_pct = 50}
	testing.expect_value(t, compute_health_score(healthy), 100)

	// One subsystem under load subtracts only its own penalty.
	cpu_pegged := Snapshot{cpu_usage = 95, mem_used_pct = 40, disk_used_pct = 50}
	testing.expect_value(t, compute_health_score(cpu_pegged), 80) // -20 cpu

	// Memory + nearly-full disk stack.
	squeezed := Snapshot{cpu_usage = 10, mem_used_pct = 95, disk_used_pct = 96}
	testing.expect_value(t, compute_health_score(squeezed), 45) // -25 mem, -30 disk

	// Everything pressured at once — still clamped to a sane range.
	maxed := Snapshot{cpu_usage = 95, mem_used_pct = 95, disk_used_pct = 96}
	score := compute_health_score(maxed)
	testing.expect(t, score >= 0 && score <= 100, "score stays in [0,100]")
	testing.expect_value(t, score, 25) // 100 - 20 - 25 - 30
}
