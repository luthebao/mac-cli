package shot

import "core:fmt"
import "core:strings"
import "core:time"

import "mc:sysx"
import "mc:util"

// cmd_full_screen captures the whole display and saves to ~/Desktop.
cmd_full_screen :: proc() -> int {
	if !ensure_permission() {
		return 1
	}
	path := build_path("screen", context.temp_allocator)
	if !capture_full_screen(path) {
		fmt.eprintln("mac-cli shot: screencapture failed")
		return 1
	}
	report_saved(path)
	return 0
}

// cmd_list_apps prints "PID  Name" for every foreground GUI app.
cmd_list_apps :: proc() -> int {
	apps, err := list_apps(context.temp_allocator)
	if err != "" {
		report_list_apps_error(err)
		return 1
	}
	if len(apps) == 0 {
		fmt.println(util.dim("No running GUI apps detected.", context.temp_allocator))
		return 0
	}
	fmt.println(util.bold("PID     Name"))
	for a in apps {
		// Odin's %-Nd zero-pads on the right (vs. C printf which space-pads).
		// Format the PID as a string first so %-Ns gives proper space padding.
		pid_str := fmt.aprintf("%d", a.pid, allocator = context.temp_allocator)
		fmt.printfln("%-6s  %s", pid_str, a.name)
	}
	return 0
}

// cmd_capture_pid resolves the PID to an app name, activates it, captures.
cmd_capture_pid :: proc(pid: int) -> int {
	apps, err := list_apps(context.temp_allocator)
	if err != "" {
		report_list_apps_error(err)
		return 1
	}
	name := ""
	for a in apps {
		if a.pid == pid {
			name = a.name
			break
		}
	}
	if name == "" {
		fmt.eprintfln("mac-cli shot: no GUI app with PID %d (run `mac-cli shot -l` to list)", pid)
		return 2
	}
	return capture_app(pid, name)
}

// cmd_interactive shows the type-to-filter picker, then captures.
cmd_interactive :: proc() -> int {
	apps, err := list_apps(context.temp_allocator)
	if err != "" {
		report_list_apps_error(err)
		return 1
	}
	if len(apps) == 0 {
		fmt.println(util.dim("No running GUI apps detected.", context.temp_allocator))
		return 0
	}
	app, picked := pick_app(apps)
	if !picked {
		fmt.println(util.dim("Cancelled.", context.temp_allocator))
		return 0
	}
	return capture_app(app.pid, app.name)
}

// capture_app captures the app's frontmost on-screen window using
// `screencapture -l <CGWindowID>`. The window contents are read from the
// window server's backing store, so the app's focus is left alone and the
// capture works even if the window is occluded.
//
// If the window isn't initially "on screen" (CG treats windows on other
// Spaces as off-screen), we activate the app — which makes macOS switch
// to the Space holding its frontmost window — then poll briefly for the
// window to register before capturing.
@(private)
capture_app :: proc(pid: int, name: string) -> int {
	if !ensure_permission() {
		return 1
	}
	win_id := find_window_id(pid)
	if win_id == 0 {
		// Likely on another Space (or minimized). Activate so macOS brings
		// the Space forward, then wait for the switch animation to settle
		// while polling for the window to appear in CGWindowList.
		if !activate_pid(pid) {
			fmt.eprintfln("mac-cli shot: failed to activate %q (PID %d) — try `mac-cli shot -s` for the full screen.", name, pid)
			return 1
		}
		win_id = wait_for_window(pid, 1500 * time.Millisecond)
	}
	if win_id == 0 {
		fmt.eprintfln("mac-cli shot: %q (PID %d) has no on-screen window — it may be minimized or hidden. Try `mac-cli shot -s` for the full screen.", name, pid)
		return 1
	}

	label := sanitize_label(name, context.temp_allocator)
	path := build_path(label, context.temp_allocator)
	if !capture_window(win_id, path) {
		fmt.eprintln("mac-cli shot: screencapture failed (check Screen Recording permission in System Settings → Privacy)")
		return 1
	}
	report_saved(path)
	return 0
}

// wait_for_window polls find_window_id every 100 ms up to `timeout`. macOS
// Space-switch animations typically settle in 300–800 ms; we cap at 1.5 s
// so an unresponsive activation doesn't hang the CLI indefinitely.
@(private)
wait_for_window :: proc(pid: int, timeout: time.Duration) -> CGWindowID {
	deadline := time.time_add(time.now(), timeout)
	for {
		id := find_window_id(pid)
		if id != 0 {
			return id
		}
		if time.since(deadline) >= 0 {
			return 0
		}
		time.sleep(100 * time.Millisecond)
	}
}

@(private)
report_saved :: proc(path: string) {
	fmt.println(util.green("✓ screenshot saved", context.temp_allocator))
	fmt.println(path)
}

// ensure_permission preflights Screen Recording, triggers the OS prompt
// when undecided, and waits briefly so a real-time grant unblocks the
// command. Without this permission both CGWindowListCopyWindowInfo and
// `screencapture` silently produce useless output (filtered window list,
// black image), so we gate every capture path through here.
//
// CGRequestScreenCaptureAccess is async — it surfaces the dialog and
// returns the *current* TCC state immediately, so we can't just re-check.
// We poll for up to PERMISSION_WAIT, then deep-link Settings if the
// user hasn't granted (covers cached-denial, where the dialog never
// appears at all).
@(private)
PERMISSION_WAIT :: 20 * time.Second

@(private)
ensure_permission :: proc() -> bool {
	if has_screen_capture_permission() {
		return true
	}
	// First call triggers the system dialog if TCC is undecided. If
	// already granted (race with another check), this returns true.
	if request_screen_capture_permission() {
		return true
	}
	fmt.println(util.dim("Waiting for Screen Recording permission… grant in the system dialog, or Ctrl-C to cancel.", context.temp_allocator))
	deadline := time.time_add(time.now(), PERMISSION_WAIT)
	for time.since(deadline) < 0 {
		time.sleep(500 * time.Millisecond)
		if has_screen_capture_permission() {
			return true
		}
	}
	// Either no dialog appeared (TCC already had a "Don't Allow" entry)
	// or the user ignored it. Deep-link Settings so they have a one-click
	// path; the binary still needs to be relaunched after the toggle.
	fmt.eprintln(util.yellow("mac-cli shot: Screen Recording permission required.", context.temp_allocator))
	fmt.eprintln("  Opening System Settings → Privacy & Security → Screen Recording…")
	fmt.eprintln("  Enable your terminal app (Terminal, iTerm, ghostty, …), quit & relaunch it, then re-run.")
	_ = sysx.run_quiet({"open", "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"})
	return false
}

// report_list_apps_error explains the underlying osascript failure to the
// user. The common case is TCC -1743 ("Not authorized to send Apple events
// to System Events") — same TCC machinery as Screen Recording but a
// different permission category (Automation), so it has its own Settings
// pane and its own dialog the user may have dismissed.
@(private)
report_list_apps_error :: proc(err: string) {
	if strings.contains(err, "-1743") || strings.contains(err, "Not authorized") {
		fmt.eprintln(util.yellow("mac-cli shot: Automation permission required to list running apps.", context.temp_allocator))
		fmt.eprintln("  Opening System Settings → Privacy & Security → Automation…")
		fmt.eprintln("  Enable \"System Events\" under your terminal app (Terminal, iTerm, ghostty, …), then re-run.")
		fmt.eprintfln("  (Underlying error: %s)", err)
		_ = sysx.run_quiet({"open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"})
		return
	}
	fmt.eprintfln("mac-cli shot: failed to list apps — %s", err)
}
