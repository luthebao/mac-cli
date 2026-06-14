# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`mac-cli` is a single-binary macOS utility written in Odin. Apple Silicon (arm64) only. Three workhorse subcommands plus a self-updater: `clean`, `clop`, `shot`, `update`.

The `clean` command is itself a small toolkit: `interactive` (scan→select→clean), `deep` (scan-everything preset), `uninstall` (bundle-id-aware app removal), `insights` (disk-usage analyzer), `monitor` (live system dashboard), plus `maintenance`, `categories`, `config`, `backup`.

## Build / test / run

```bash
make build                           # → build/mac-cli (debug)
make release                         # → build/mac-cli-vX.Y.Z-darwin-arm64.tar.gz
make test                            # odin test for fsx, clean/store, clean/monitor, clean/cmd
make build VERSION=0.2.0-dev         # override embedded version
```

Run a single package's tests directly:

```bash
odin test src/fsx -collection:mc=src -define:VERSION=0.1.0
odin test src/clean/store -collection:mc=src -define:VERSION=0.1.0
```

The `mc:` import prefix (e.g. `import "mc:cli"`) is the collection alias defined in `ols.json` and the Makefile's `ODIN_FLAGS`. Always pass `-collection:mc=src` when invoking `odin` directly.

`VERSION` is injected at build time via `-define:VERSION=x.y.z`. CI reads the git tag; `make` falls back to the literal in `src/main.odin`.

## Architecture

### Top-level layout

```bash
src/main.odin               entry — parses argv[1], dispatches to a package
src/cli/                    shared CLI machinery (flag parser, menu, help text)
src/clean/                  disk cleaner
src/clop/                   image/video pipeline (shells out to format CLIs)
src/shot/                   screenshots
src/update/                 self-updater (curl-pipes install.sh)
src/fsx/                    filesystem helpers (paths, sizes, deletes)
src/sysx/                   subprocess helpers (run_capture, run_quiet)
src/util/                   color, clipboard, small text helpers
```

### Import direction

`clean`, `clop`, `shot`, `update` all import `mc:cli`. `cli` MUST NOT import any of them — that would cycle. The `cli` package speaks to command packages indirectly through the `MenuAction` enum + `[]string` args, with `main.odin` doing the routing. Keep it that way.

### Command dispatch

Every top-level command (`clean`, `clop`, `shot`, `update`) exposes a `dispatch :: proc(args: []string) -> int`. Exit codes are propagated to `os.exit` by `main.odin`. The dispatch is the routing layer; the per-mode logic lives in sibling files (`cmd_*`, `run_*`).

Inside `clean`, the same pattern repeats: `clean.dispatch` routes to `clean/cmd/run_<name>` procs (config, backup, maintenance, uninstall, insights, monitor, categories, interactive), each of which is itself a sub-dispatcher. `deep` is a sentinel that re-enters `run_interactive` with `--deep` (scan everything incl. risky; pre-select safe/moderate). `analyze`/`status` are accepted as aliases for `insights`/`monitor`.

The heavy logic for the two newer features lives in dedicated sub-packages so it's testable apart from the TUI/IO:

- `src/clean/insights/` — directory + file size ranking (one `du -k -d 1` for child sizes, a directory read for top-level files, `find … -size +100000k` for largest files) and "hidden space" detection (caches, iOS backups, old downloads). `cmd/insights.odin` renders the bar-chart report.
- `src/clean/monitor/` — `collect()` gathers CPU/memory/disk/network/power by shelling out to native macOS tools (`sysctl`, `vm_stat`, `df`, `netstat -ibn`, `ps`, `pmset`, `sw_vers`); `render()` builds the dashboard; `health.odin` holds the tunable health-score policy. `cmd/monitor.odin` drives the alt-screen 1s refresh loop. NB: pass `-n` to `netstat` — without it, name resolution stalls ~5s when stdout is a pipe.

The destructive scan→clean flow (`interactive`/`deep`) is gated on `tui.is_interactive()`: when stdin isn't a TTY it refuses to run, because confirmation prompts silently take their defaults and `deep` arrives with rows pre-selected. Live/refreshing views use `tui.enter_alt`/`leave_alt` + `tui.poll_key(timeout)`.

### Deletion safety (`fsx/delete.odin`) — two tiers

`safe_delete` enforces an allowlist; understand the tiers before adding scanners:

- **Strict (`is_path_safe`)** — the default for bulk/automated cache categories. A path must sit under a `SAFE_ROOTS` prefix (`*` = one segment). `SAFE_ROOTS` are *contents-only* (deleting the root dir itself is refused) **unless** also listed in `SAFE_LEAF_ROOTS` — pure regenerable caches (Xcode DerivedData, `.cargo/registry`, the `…/*/Cache` Electron dirs, …) that may be deleted wholesale. `DANGER_PATHS` always wins.
- **Reviewed (`is_path_safe_reviewed`)** — for the file-selection categories (`supports_file_selection = true`: Large Files, Duplicate Files, old Downloads), which surface arbitrary files from anywhere under `$HOME`. `clean_items` passes `reviewed = cat.supports_file_selection` to `safe_delete`; reviewed paths are accepted if they're absolute, strictly inside `$HOME`, and not under a `DANGER_PATH`. This is additive — it never loosens the strict tier for bulk categories.

A common symptom of getting this wrong is a scanner surfacing a path that `safe_delete` then refuses with "refused (path not safe)" — meaning the scanner and the allowlist disagree. Fix the allowlist (leaf root / reviewed flag), don't weaken `DANGER_PATHS`.

### TUI menu system (`cli/menu.odin`)

This is the heart of the UX and the most important rule for adding new commands. Read `cli/menu.odin` before adding a subcommand.

- **Every command opens a TUI menu by default.** Running `mac-cli`, `mac-cli clean`, `mac-cli clean config`, etc. with no further args MUST drop the user into a menu listing the available subcommands.
- **The menu shows every subcommand, including `help` and `← back`.** The `← back` row navigates up one level; `Esc` cancels and exits the program entirely (propagates up). These behave differently — see `PickStatus` (Selected / Back / Cancel).
- **Drill until a leaf is executed.** If a subcommand has its own subcommands (e.g. `clean config`, `clean backup`, `clean maintenance`), the menu MUST recurse: pick → sub-menu → leaf.
- **Empty args means "show the menu". Default leaves need an explicit sentinel.** A leaf that previously meant "the default behavior on empty args" (e.g. `clean`'s interactive scan, `shot`'s app picker, `update`'s install-if-newer) cannot return empty args from the menu or it would infinite-loop back into `pick_at`. Pick a string sentinel (`"interactive"`, `"install"`, …) and route it explicitly in the dispatch's switch.
- **Args storage must outlive the menu call.** `MenuItem.args` is a `[]string`. Build the backing array at package scope (`@(private="file") ARGS_FOO := [?]string{...}`) and slice it (`ARGS_FOO[:]`). Compound literals inside procs dangle; Odin will reject the return.
- **Tree entry points.** `cli.pick_at(path...)` is how a dispatch enters its own subtree (e.g. `cli.pick_at("clean", "config")` for clean/config). The leaf args are stripped of the path prefix before being returned, so the caller sees args relative to its own level. `cli.run_menu(version)` is reserved for `main.odin`'s top-level entry.

When adding a new subcommand:

1. Add the dispatch case (and its sentinel if it's the default leaf).
2. Add the MenuItem to the right subtree in `cli/menu.odin`, with a package-scope `ARGS_*` backing array.
3. If the new subcommand has its own subcommands, add a `children = ...` subtree and update the new dispatch's empty-args branch to call `cli.pick_at(<parent>, <name>)`.
4. The `help` leaf at each level should return args that route to the dispatch's existing `--help` handling — no new help wiring needed.

### Non-TTY fallback

`cli.run_menu` falls back to `print_welcome` when stdin isn't a TTY (so CI/pipe invocations get a textual command list). `cli.pick_at` currently returns silently in the same situation — be aware when adding new command paths that piped invocation will just exit 0 with no output.

### Subprocess discipline

Shelling out goes through `mc:sysx`. Use `sysx.run_capture` when you need stdout, `sysx.run_quiet` when you only need success/failure. Do not call `core:os/exec` directly — `sysx` is where allocator handling and stderr policy live.

### clop's tool prompting

`clop` shells out to format-specific CLIs (`pngquant`, `ffmpeg`, `cwebp`, `heif-enc`, `exiftool`, …). When a required tool is missing, it interactively offers `brew install`. In non-interactive contexts the prompt silently declines — operations skip the file rather than failing the whole batch.

## Release flow

Tag `vX.Y.Z` → `.github/workflows/release.yml` builds on macos-14, runs `make release VERSION=X.Y.Z`, publishes the tarball to a GitHub Release. `install.sh` and `mac-cli update` both pull from `releases/latest`. There is no manual version bump — the tag value is injected at build time.
