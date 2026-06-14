package cli

import "core:fmt"

TOP_USAGE :: `mac-cli — multi-purpose macOS command-line tool

USAGE
  mac-cli <command> [args...]

COMMANDS
  clean        Clean caches, logs, junk, and unused files
  clop         Optimise / downscale / convert images and videos
  shot         Take a screenshot (full screen or a specific app)
  update       Update mac-cli itself to the latest release
  help [cmd]   Show help (optionally for a specific command)
  version      Print version

EXAMPLES
  mac-cli clean
  mac-cli clean --risky
  mac-cli clean categories
  mac-cli clop -o photo.jpg
  mac-cli clop -d 0.5 ~/Videos/clip.mp4
  mac-cli shot
  mac-cli shot -s
  mac-cli shot -l
  mac-cli update
  mac-cli update --check
  mac-cli help clean
`

CLEAN_USAGE :: `mac-cli clean — disk cleaner for macOS

USAGE
  mac-cli clean [flags]                 Interactive scan → select → clean
  mac-cli clean <subcommand> [flags]

FLAGS (default interactive mode)
  -r, --risky            Include risky categories (downloads, iOS backups, …)
  -f, --file-picker      Force file picker for ALL supported categories
  -A, --absolute-paths   Show absolute paths instead of abbreviated
      --no-progress      Disable progress bars

SUBCOMMANDS
  deep                   Deep clean — scan everything, safe categories pre-picked
  uninstall              Remove apps + leftovers (bundle-id aware)
  insights               Show where disk space went (largest dirs/files)
  monitor                Live CPU/memory/disk/network/power dashboard
  maintenance            Maintenance tasks (DNS flush, purgeable, snapshots)
  categories             List the cleanable categories
  config                 Manage ~/.mac-cli/clean/config.json
  backup                 Manage pre-delete backups

EXAMPLES
  mac-cli clean
  mac-cli clean deep
  mac-cli clean --risky -f
  mac-cli clean insights ~/Library
  mac-cli clean monitor
  mac-cli clean monitor --json
  mac-cli clean uninstall --dry-run
  mac-cli clean maintenance --dns
`

print_top_help :: proc() {
	fmt.print(TOP_USAGE)
}

SHOT_USAGE :: `mac-cli shot — take a macOS screenshot

USAGE
  mac-cli shot              Interactive picker (type to filter, ↑↓ navigate, ⏎ select)
  mac-cli shot -s           Capture the whole screen
  mac-cli shot -l           List running GUI apps with PID and name
  mac-cli shot -p <pid>     Capture the app with the given PID

All screenshots are saved to ~/Desktop as .png files.
First run may prompt for Screen Recording permission in System Settings → Privacy.

EXAMPLES
  mac-cli shot
  mac-cli shot -s
  mac-cli shot -l
  mac-cli shot -p 1234
`

CLOP_USAGE :: `mac-cli clop — optimise, downscale, convert media files

USAGE
  mac-cli clop -o <path>              Optimise in place (same format)
  mac-cli clop -d <factor> <path>     Downscale by factor (0.5 or 50%)
  mac-cli clop -c <format> <path>     Convert image to webp|heic|avif
  mac-cli clop -s <path>              Strip EXIF metadata

If <path> is a directory, every supported file inside is processed.
Add -r to recurse into subdirectories. Add -a for aggressive presets.
Add -k to keep an .orig backup beside each modified file.

OPERATIONS
  -o, --optimise            pngquant / jpegoptim / gifsicle / ffmpeg
  -d, --downscale  <f>      vipsthumbnail (images), ffmpeg -vf scale (videos)
  -c, --convert    <fmt>    cwebp (webp), heif-enc (heic, avif)
  -s, --stripexif           exiftool (keeps orientation only)

MODIFIERS
  -a, --aggressive          stronger compression (visible quality loss)
  -r, --recursive           recurse into subdirectories
  -k, --keep                save <path>.orig before overwriting
  -h, --help                show this help

SUPPORTED EXTENSIONS
  images:  .png .jpg .jpeg .gif
  videos:  .mp4 .mov .m4v
  pdfs:    .pdf  (planned; currently skipped)

EXAMPLES
  mac-cli clop -o ~/Pictures/screenshot.png
  mac-cli clop -o ~/Pictures -r          # all images+videos under ~/Pictures
  mac-cli clop -d 50% ~/Videos/clip.mp4
  mac-cli clop -c webp ~/Pictures/cover.png
  mac-cli clop -s ~/Phone/IMG_2156.jpg

REQUIRED TOOLS
  clop shells out to format-specific CLIs. On first use of a format,
  if the tool is missing, mac-cli will prompt to brew install it (declines
  silently in non-interactive contexts). Toolchain:
    images:  pngquant jpegoptim gifsicle vips webp libheif exiftool
    videos:  ffmpeg

  To install everything up front:
    brew install pngquant jpegoptim gifsicle ffmpeg vips webp libheif exiftool
`

UPDATE_USAGE :: `mac-cli update — pull the latest release binary

USAGE
  mac-cli update              Check for a new release; install it if found.
  mac-cli update --check      Only report whether a newer release exists.
                              Exits non-zero when an update is available.
  mac-cli update --force      Re-run the installer even if already current.

ENVIRONMENT
  PREFIX=<dir>                Install dir for the new binary
                              (forwarded to the install script).
  VERSION=<x.y.z>             Pin a specific release instead of latest.

EXAMPLES
  mac-cli update
  mac-cli update --check
  PREFIX=$HOME/.local/bin mac-cli update
`

print_help :: proc(topic: string) {
	switch topic {
	case "", "help":
		fmt.print(TOP_USAGE)
	case "clean":
		fmt.print(CLEAN_USAGE)
	case "clop":
		fmt.print(CLOP_USAGE)
	case "shot":
		fmt.print(SHOT_USAGE)
	case "update":
		fmt.print(UPDATE_USAGE)
	case:
		fmt.eprintfln("mac-cli help: unknown topic %q", topic)
		fmt.eprint(TOP_USAGE)
	}
}
