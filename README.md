# mac-cli

A multi-purpose macOS command-line tool, written in [Odin](https://odin-lang.org/).

## Install

One-liner (no Odin required — pulls the latest release binary):

```bash
curl -fsSL https://raw.githubusercontent.com/luthebao/mac-cli/main/install.sh | bash
```

Pin a version or override the install prefix via env vars:

```bash
curl -fsSL https://raw.githubusercontent.com/luthebao/mac-cli/main/install.sh \
  | VERSION=0.1.0 PREFIX=$HOME/.local/bin bash
```

## Usage

```bash
mac-cli                              # print help
mac-cli version                      # print version
mac-cli clean                        # interactive cleaner
mac-cli clean --risky                # include risky categories
mac-cli clean categories             # list all 16 cleanable categories
mac-cli clean uninstall              # remove apps + their leftovers
mac-cli clean maintenance --dns      # flush DNS cache
mac-cli clean config --init          # create ~/.mac-cli/clean/config.json
mac-cli clean backup --list          # list pre-delete backups
```

## Build from source

Requires Odin (any recent `dev-*` build).

```bash
git clone https://github.com/luthebao/mac-cli.git
cd mac-cli
make build         # → build/mac-cli
make test
make install       # → /usr/local/bin/mac-cli (or ~/.local/bin)
```

## License

MIT.

## Releasing

Releases are driven by git tags. Tagging `vX.Y.Z` triggers
`.github/workflows/release.yml`, which:

1. Builds `mac-cli` on **macos-14** (arm64), injecting the tag value into the
   binary via `make release VERSION=X.Y.Z` (no source edit needed).
2. Tars the binary as `mac-cli-vX.Y.Z-darwin-arm64.tar.gz`.
3. Publishes it to a GitHub Release — which `install.sh` then pulls from.

> Homebrew tap auto-bump is intentionally disabled for now; it will be wired
> back in once the install flow stabilises.

### Cutting a release

```bash
git tag v0.1.0
git push origin v0.1.0
```

The tag name (minus the leading `v`) becomes the binary's version — no need
to edit `src/main.odin` first. For a local debug build with a custom version,
pass it through `make`:

```bash
make build VERSION=0.2.0-dev
```
