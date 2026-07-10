package cli

import "core:strings"

// Flags is a minimal arg parser shared across namespaces.
// We don't pull in an external parser — flags are few and uniform.
//
// Supported forms:
//   --flag             → bool true
//   --flag=value       → string value
//   --flag value       → string value (next token consumed)
//   -x                 → short bool true
//   -x value           → short value
//   Combined shorts (`-rf`) are NOT supported (avoids ambiguity with values).
//
// Anything not starting with `-` is collected as a positional argument.

Flag :: struct {
	name:    string, // long form, no leading `--`
	short:   string, // single char, no leading `-`; "" if none
	takes_value: bool,
}

ParsedFlags :: struct {
	values:    map[string]string, // long-name → value (or "true" for bool flags)
	positional: [dynamic]string,
}

// parse extracts known flags from args. Unknown flags are returned as-is
// in positional (so callers can choose to error or pass them through).
parse :: proc(args: []string, spec: []Flag, allocator := context.allocator) -> (out: ParsedFlags) {
	out.values = make(map[string]string, len(spec), allocator)
	out.positional = make([dynamic]string, 0, len(args), allocator)

	i := 0
	for i < len(args) {
		a := args[i]
		matched := false

		// --long or --long=value
		if strings.has_prefix(a, "--") {
			body := a[2:]
			name := body
			val_inline := ""
			has_inline := false
			if eq := strings.index_byte(body, '='); eq >= 0 {
				name = body[:eq]
				val_inline = body[eq+1:]
				has_inline = true
			}
			for f in spec {
				if f.name == name {
					if f.takes_value {
						if has_inline {
							out.values[name] = val_inline
						} else if i+1 < len(args) {
							out.values[name] = args[i+1]
							i += 1
						} else {
							out.values[name] = ""
						}
					} else {
						out.values[name] = "true"
					}
					matched = true
					break
				}
			}
		} else if len(a) >= 2 && a[0] == '-' && a[1] != '-' {
			short := a[1:]
			for f in spec {
				if f.short == short {
					if f.takes_value {
						if i+1 < len(args) {
							out.values[f.name] = args[i+1]
							i += 1
						} else {
							// Trailing `-x` with the value forgotten — record it
							// as empty (same as the long-flag path) so callers see
							// a missing value, not the literal string "true".
							out.values[f.name] = ""
						}
					} else {
						out.values[f.name] = "true"
					}
					matched = true
					break
				}
			}
		}

		if !matched {
			append(&out.positional, a)
		}
		i += 1
	}
	return
}

// bool_flag returns true iff the flag was set to "true".
bool_flag :: proc(p: ParsedFlags, name: string) -> bool {
	v, ok := p.values[name]
	return ok && v == "true"
}

// string_flag returns the value or default.
string_flag :: proc(p: ParsedFlags, name: string, default := "") -> string {
	v, ok := p.values[name]
	if !ok {
		return default
	}
	return v
}
