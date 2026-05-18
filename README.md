# mac-cli

A multi-purpose macOS command-line tool, written in [Odin](https://odin-lang.org/).

Currently ships an Apple Silicon (`arm64`) build only.

## Install

One-liner — pulls the latest release binary, no Odin toolchain required:

```bash
curl -fsSL https://raw.githubusercontent.com/luthebao/mac-cli/main/install.sh | bash
```

The script downloads `mac-cli-vX.Y.Z-darwin-arm64.tar.gz` from the latest
GitHub Release, picks a sensible install dir (`/usr/local/bin` if writable,
otherwise `~/.local/bin`), strips the macOS quarantine xattr so Gatekeeper
doesn't block the first run, and prints a `PATH` hint if the chosen dir
isn't already on `$PATH`.

## Agent skill (Claude Code)

If you use [Claude Code](https://claude.com/claude-code), install the
companion agent skill so Claude can drive `mac-cli` on your behalf — cleaning
caches, taking app-specific screenshots, optimising media, and so on:

```bash
npx skills add luthebao/mac-cli
```

The skill assumes the `mac-cli` binary is already on `$PATH`, so install that
first (see above).

## Update

The binary updates itself — same install logic, no flags needed:

```bash
mac-cli update            # install latest if newer
mac-cli update --check    # report only; exits non-zero when update available
mac-cli update --force    # re-run the installer even if already current
```

## Usage

```bash
mac-cli                              # interactive command menu
mac-cli help <command>               # detailed help for a command
mac-cli version                      # print version
```

### `clean` — disk cleaner

```bash
mac-cli clean                        # interactive cleaner
mac-cli clean --risky                # include risky categories
mac-cli clean -f                     # force file picker on every category
mac-cli clean categories             # list all 16 cleanable categories
mac-cli clean uninstall              # remove apps + their leftovers
mac-cli clean maintenance --dns      # flush DNS cache
mac-cli clean config --init          # create ~/.mac-cli/clean/config.json
mac-cli clean backup --list          # list pre-delete backups
```

### `clop` — image & video optimiser

```bash
mac-cli clop                         # interactive picker (operation + files)
mac-cli clop -o photo.png            # optimise in place
mac-cli clop -o ~/Pictures -r        # recurse into a directory
mac-cli clop -d 50% clip.mp4         # downscale by factor
mac-cli clop -c webp cover.png       # convert image format
mac-cli clop -s IMG_2156.jpg         # strip EXIF metadata
mac-cli clop -o -a -k photo.jpg      # aggressive preset, keep .orig backup
```

Operations shell out to format-specific CLIs (`pngquant`, `jpegoptim`,
`gifsicle`, `ffmpeg`, `vips`, `cwebp`, `heif-enc`, `exiftool`). Missing tools
trigger an interactive `brew install` prompt on first use. Supported formats:
`.png .jpg .jpeg .gif` (images) and `.mp4 .mov .m4v` (videos).

### `shot` — screenshots

```bash
mac-cli shot                         # interactive picker (type to filter)
mac-cli shot -s                      # capture full screen
mac-cli shot -l                      # list running GUI apps with PIDs
mac-cli shot -p 1234                 # capture a specific app by PID
```

All screenshots land in `~/Desktop` as PNGs. First run may prompt for the
Screen Recording permission in System Settings → Privacy.

### `update` — self-updater

See [Update](#update) above.

## Build from source

Requires Odin (any recent `dev-*` build).

```bash
git clone https://github.com/luthebao/mac-cli.git
cd mac-cli
make build                           # → build/mac-cli
make test
make install                         # → /usr/local/bin/mac-cli (or ~/.local/bin)
```

Override the embedded version for local builds:

```bash
make build VERSION=0.2.0-dev
./build/mac-cli version              # → mac-cli 0.2.0-dev
```

## License

MIT.

## Releasing

Releases are driven by git tags. Tagging `vX.Y.Z` triggers
`.github/workflows/release.yml`, which:

1. Builds `mac-cli` on **macos-14** (arm64), injecting the tag value into the
   binary via `make release VERSION=X.Y.Z` (no source edit needed).
2. Tars the binary as `mac-cli-vX.Y.Z-darwin-arm64.tar.gz`.
3. Publishes it to a GitHub Release — which `install.sh` and `mac-cli update`
   pull from.

### Cutting a release

```bash
git tag v0.1.0
git push origin v0.1.0
```

The tag name (minus the leading `v`) becomes the binary's version — no source
edits required.
