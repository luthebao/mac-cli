package main

import "core:fmt"
import "core:os"

import "mc:cli"
import "mc:clean"
import "mc:clop"
import "mc:shot"
import "mc:update"

// Default version. Override at build time with `-define:VERSION=x.y.z`
// (the Makefile and release workflow inject the tag value this way).
VERSION :: #config(VERSION, "0.1.0")

main :: proc() {
	args := os.args[1:]

	if len(args) == 0 {
		res := cli.run_menu(VERSION)
		switch res.action {
		case .None, .Quit:
			return
		case .Help:
			cli.print_help("")
			return
		case .Version:
			fmt.printfln("mac-cli %s", VERSION)
			return
		case .Clean:
			code := clean.dispatch(res.args)
			if code != 0 { os.exit(code) }
			return
		case .Clop:
			code := clop.dispatch(res.args)
			if code != 0 { os.exit(code) }
			return
		case .Shot:
			code := shot.dispatch(res.args)
			if code != 0 { os.exit(code) }
			return
		case .Update:
			code := update.dispatch(res.args, VERSION)
			if code != 0 { os.exit(code) }
			return
		}
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
	case "clop":
		code := clop.dispatch(rest)
		if code != 0 {
			os.exit(code)
		}
	case "shot":
		code := shot.dispatch(rest)
		if code != 0 {
			os.exit(code)
		}
	case "update":
		code := update.dispatch(rest, VERSION)
		if code != 0 {
			os.exit(code)
		}
	case:
		fmt.eprintfln("mac-cli: unknown command %q", cmd)
		fmt.eprintln("run `mac-cli help` for available commands")
		os.exit(2)
	}
}
