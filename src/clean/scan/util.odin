package clean_scan

import "core:strconv"

parse_float :: proc(s: string) -> (f64, bool) {
	return strconv.parse_f64(s)
}
