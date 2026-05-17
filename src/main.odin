package main

import "core:fmt"
import "core:os"

import "mc:cli"
import "mc:clean"

// Bumped manually per release. Release workflow uses sed to sync this
// with the git tag before building, so CI artifacts always carry the tag value.
VERSION :: "0.1.0"

main :: proc() {
	args := os.args[1:]

	if len(args) == 0 {
		cli.print_welcome(VERSION)
		return
	}

	cmd := args[0]
	rest := args[1:]

	switch cmd {
	case "version", "--version", "-V":
		fmt.printfln("mac-cli %s", VERSION)
	case "help", "--help", "-h":
		topic := ""
		if len(rest) > 0 {
			topic = rest[0]
		}
		cli.print_help(topic)
	case "clean":
		code := clean.dispatch(rest)
		if code != 0 {
			os.exit(code)
		}
	case:
		fmt.eprintfln("mac-cli: unknown command %q", cmd)
		fmt.eprintln("run `mac-cli help` for available commands")
		os.exit(2)
	}
}
