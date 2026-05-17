# mac-cli

A multi-purpose macOS command-line tool, written in [Odin](https://odin-lang.org/).

## Install

```bash
brew tap luthebao/mac-cli
brew install mac-cli
```

Or as a one-liner: `brew install luthebao/mac-cli/mac-cli`.

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

1. Builds `mac-cli` on **macos-14** (arm64) and **macos-13** (amd64).
2. Tars each binary as `mac-cli-vX.Y.Z-darwin-{arm64,amd64}.tar.gz`.
3. Publishes them to a GitHub Release.
4. Auto-PRs `luthebao/homebrew-mac-cli` with the new version + SHAs.

### One-time setup

1. Create a sibling repo named **`homebrew-mac-cli`** under `luthebao/`.
   Homebrew requires the `homebrew-` prefix.
2. Generate a fine-grained Personal Access Token with `contents: write` and
   `pull_requests: write` scoped to `luthebao/homebrew-mac-cli`.
3. Add it to this repo's secrets as **`HOMEBREW_TAP_TOKEN`**.

The first release will create `Formula/mac-cli.rb` in the tap repo
automatically.

### Cutting a release

```bash
# bump VERSION line in src/main.odin first
git tag v0.1.0
git push origin v0.1.0
```

Then wait for the workflow to finish and merge the auto-PR in `homebrew-mac-cli`.
