package clean_cmd

import "core:encoding/json"
import "core:fmt"

import "mc:cli"
import "mc:clean/store"

run_config :: proc(args: []string) -> int {
	spec := []cli.Flag{
		{name = "init", takes_value = false},
		{name = "show", takes_value = false},
		{name = "help", short = "h", takes_value = false},
	}
	p := cli.parse(args, spec)

	if cli.bool_flag(p, "help") {
		fmt.println(
`mac-cli clean config — manage ~/.mac-cli/clean/config.json

USAGE
  mac-cli clean config --init    Create default config (won't overwrite)
  mac-cli clean config --show    Print current effective config
`)
		return 0
	}

	if cli.bool_flag(p, "init") {
		if store.config_exists() {
			fmt.println("Configuration already exists at", store.config_path(context.temp_allocator))
			return 0
		}
		path, err := store.init_config()
		if err != "" {
			fmt.eprintln("config --init:", err)
			return 1
		}
		fmt.println("Created", path)
		return 0
	}

	if cli.bool_flag(p, "show") {
		cfg := store.load_config()
		data, jerr := json.marshal(cfg, {pretty = true, use_spaces = false}, context.temp_allocator)
		if jerr != nil {
			fmt.eprintln("config --show: failed to encode config:", jerr)
			return 1
		}
		fmt.println(string(data))
		return 0
	}

	fmt.println("Use --init to create or --show to display the config.")
	return 0
}
