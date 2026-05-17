package sysx

import "core:os"
import "core:strings"

// RunResult is the captured outcome of a subprocess run.
RunResult :: struct {
	stdout:    string,
	stderr:    string,
	exit_code: int,
	ok:        bool, // true iff the process exited normally with code 0
}

// run runs a command and captures stdout/stderr. Returns ok=false on any
// error (spawn failure, non-zero exit, signal termination).
//
// Returned strings are allocated with `allocator` and owned by the caller.
//
// NOTE: argv is passed directly to the OS — there is NO shell interpolation,
// so untrusted strings in command args cannot inject shell metacharacters.
run :: proc(command: []string, allocator := context.allocator) -> RunResult {
	desc := os.Process_Desc{ command = command }
	proc_call := os.process_exec
	state, stdout, stderr, err := proc_call(desc, allocator)

	out := RunResult{
		stdout = string(stdout),
		stderr = string(stderr),
	}
	if err != nil {
		out.ok = false
		return out
	}
	out.exit_code = state.exit_code
	out.ok = state.exited && state.exit_code == 0
	return out
}

// run_capture trims trailing whitespace from stdout — handy for commands
// like `brew --cache` whose only purpose is to print a path.
run_capture :: proc(command: []string, allocator := context.allocator) -> RunResult {
	r := run(command, allocator)
	r.stdout = strings.trim_right_space(r.stdout)
	return r
}

// run_quiet discards stdout/stderr; for fire-and-forget side effects.
run_quiet :: proc(command: []string) -> bool {
	r := run(command, context.temp_allocator)
	return r.ok
}
