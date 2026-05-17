package sysx

import "core:strings"
import "core:testing"

@(test)
test_run_echo :: proc(t: ^testing.T) {
	r := run_capture({"/bin/echo", "hello"})
	testing.expect(t, r.ok, "echo should succeed")
	testing.expect_value(t, r.exit_code, 0)
	testing.expect(t, strings.contains(r.stdout, "hello"), "stdout should contain 'hello'")
}

@(test)
test_run_false :: proc(t: ^testing.T) {
	r := run({"/usr/bin/false"})
	testing.expect(t, !r.ok, "false should fail")
	testing.expect_value(t, r.exit_code, 1)
}

@(test)
test_run_missing_binary :: proc(t: ^testing.T) {
	r := run({"/no/such/binary/anywhere"})
	testing.expect(t, !r.ok, "missing binary should report not-ok")
}
