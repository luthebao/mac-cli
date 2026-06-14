---
name: mac-cli
description: Drive the `mac-cli` binary on Apple Silicon macOS to clean disk junk, analyze disk usage, monitor live system stats, take screenshots, and optimise/convert/downscale/strip-EXIF images and videos. Use this skill whenever the user asks to free up disk space, clear caches/logs, uninstall a Mac app cleanly, flush DNS, thin Time Machine snapshots, see where disk space went / find large files, check live CPU/memory/disk/network usage, screenshot a specific running app, compress or convert a media file (png/jpg/gif/mp4/mov), strip image metadata, or anything that sounds like "shrink this video", "make this png smaller", "clean my Mac", "what's eating my disk", "how's my Mac doing", "screenshot Slack" — even when they don't name `mac-cli` directly. Apple Silicon (arm64) only.
---

# mac-cli

`mac-cli` is a single-binary macOS utility with three workhorse subcommands plus a self-updater:

| Subcommand | What it does |
| ---------- | ------------ |
| `clean`    | Disk toolkit — cache/log/junk cleaning, a deep-clean preset, bundle-id-aware app uninstall, disk-usage insights, a live system monitor, plus maintenance tasks |
| `clop`     | Media pipeline — optimise / downscale / convert / strip EXIF on images and videos |
| `shot`     | Screenshot — full screen or a single running GUI app by PID |
| `update`   | Self-update from GitHub Releases |

`clean` is itself a small toolkit. Its subcommands: `interactive` (default scan→select→clean), `deep` (scan-everything preset), `uninstall`, `insights` (disk analyzer), `monitor` (live dashboard), `maintenance`, `categories`, `config`, `backup`. `analyze`/`status` are accepted as aliases for `insights`/`monitor`.

The binary lives at `mac-cli` on `$PATH` once installed. Apple Silicon only — refuse to run this on Intel Macs.

## Before doing anything

Confirm the binary is installed and on `$PATH`:

```bash
command -v mac-cli && mac-cli version
```

If absent, the install one-liner is `curl -fsSL https://raw.githubusercontent.com/luthebao/mac-cli/main/install.sh | bash`. Don't run installers without the user's say-so.

When in doubt about a flag, run `mac-cli help <subcommand>` — it's the authoritative reference and may be ahead of this skill.

## The interactive-vs-flagged rule (read this first)

`mac-cli` is friendly to humans: many subcommands open a TUI picker or full-screen view when run bare. Under an agent there's no TTY to drive them, so prefer the flagged/one-shot form. Two behaviors to know:

- The destructive `clean` flows (bare `clean`, `clean interactive`, `clean deep`) now **refuse without a TTY** — they print a short message and exit 0 instead of hanging or deleting. Safe, but you still can't *drive* them as an agent; use the non-interactive subcommands or hand the command to the user.
- `clean monitor` auto-detects a non-TTY and prints a **single snapshot** instead of the live view (or use `--json`). `clean insights` is one-shot by design. Both are read-only and agent-friendly.
- `shot` (bare) still opens an interactive picker that **will hang** under an agent — always use a flag.

Rules of thumb:

- `clean` → use a non-interactive subcommand (`categories`, `insights`, `monitor --json`, `maintenance --dns`, `uninstall --dry-run`, `backup --list`, `config --show`) rather than bare `clean`/`deep` (those need a TTY).
- `shot` → use `-s` (full screen), `-l` (list with PIDs), or `-p <pid>` (specific app). Never bare `shot`.
- `clop` → already flag-driven, but on first use of a format it may prompt to `brew install` a missing tool; in non-interactive contexts it declines silently and the operation fails. Verify required tools exist before invoking on a large batch (see `clop` § below).

If the user explicitly wants the interactive UX (they're sitting at the terminal and asked for it), tell them the exact command to type — don't try to drive it yourself.

---

## `clean` — disk cleaner

### The category taxonomy is a safety boundary

`mac-cli clean categories` groups categories into three buckets — **treat these as a hard guardrail**:

- 🟢 **Safe** — Trash, temp files, browser cache, Homebrew cache + old versions, app caches (Electron/Chromium `Cache`/`Code Cache`/`GPUCache`), system-wide caches, orphaned symlinks, Docker. Fine to clean without ceremony.
- 🟡 **Moderate** — user caches, system logs, dev caches (npm/yarn/pip/cargo/gradle/bundle/DerivedData/CocoaPods), orphaned node_modules, orphaned launch agents. Apps may need to rebuild state; logs help debugging.
- 🔴 **Risky** — old Downloads, iOS backups, Mail attachments, large files, duplicates. Real data lives here. **Never** include risky categories unless the user has explicitly named one of them or said "include risky" / "clean everything".

> Note: the **Language Files** category (stripping `.lproj` localizations from `/Applications`) was **removed** — it breaks app code signatures and is blocked by the safety layer. Don't suggest it.
>
> **Large Files** and **Duplicate Files** are *file-selection* categories: in the interactive UI the user presses `→` to drill in and tick individual files (kept-newest logic for duplicates). They delete hand-picked files from anywhere under `$HOME`, so they're inherently 🔴.

The `--risky` flag is what unlocks 🔴 categories; `clean deep` turns it on implicitly (see below). Treat it like `rm -rf` — opt-in, narrated, and never your default.

### Confirmation policy (applies before any deletion runs)

Match the number of confirmations to the bucket of the *most destructive* category in the planned operation:

- 🟢 **Safe** — no extra confirmation beyond the user's initial ask. Narrate what will run, then run it.
- 🟡 **Moderate** — **confirm once**. State exactly what will be deleted (paths, age thresholds, approximate size when known) and wait for an explicit "yes" / "go ahead" / equivalent before invoking the command. A vague "ok cool" earlier in the conversation does not count.
- 🔴 **Risky** — **confirm twice**. First confirmation: show the dry-run output or category list and get an explicit go-ahead. Second confirmation: immediately before invoking the destructive command, restate the action in one sentence ("About to delete <N> items from <category> — proceed?") and wait for a second explicit "yes". Both confirmations must be after the user has seen what will actually be removed.

Apply the same rule across subcommands, not just `clean`:

- `clean insights` and `clean monitor` are **read-only** — no confirmation, run freely. They never delete anything.
- `clean deep` is 🔴 — it scans every category including risky ones and pre-checks the safe/moderate ones for deletion. It requires a TTY (an agent can't drive it), so when a user wants it, hand them the command and let them review the pre-checked list before they confirm in the TUI.
- `clean uninstall` is 🔴 — always run `--dry-run` first (confirm #1 on the listing), then restate before `--yes` (confirm #2). It now reads each app's bundle id and sweeps ~11 leftover locations (Application Support, Caches, Containers, Group Containers, HTTPStorages, WebKit, Saved State, Logs, Preferences, Cookies, LaunchAgents), so the dry-run list is more thorough than before — review it.
- `clean maintenance --timemachine` deletes snapshots → 🔴, double-confirm.
- `clean maintenance --purgeable` / `--dns` → 🟡, single confirm.
- `clean backup --clean` deletes old backup sessions → 🟡, single confirm.
- `clop -o` / `-s` overwrite originals in place → 🟡 if originals are recoverable (e.g. from git or a sync service), 🔴 if they are user-supplied originals with no other copy. When in doubt, add `-k` and skip the upgrade in confirmation count.
- `update` (bare, not `--check`) replaces the binary → 🟡, single confirm unless the user explicitly asked to update in this turn.

If the user has *already* explicitly requested the destructive action in this turn with full specifics ("delete the iOS backups in `~/Library/Application Support/MobileSync/Backup`"), that counts as the first confirmation for 🔴 — still do the pre-execution restate as the second.

Never silently downgrade the count to keep momentum. The cost of asking is a sentence; the cost of an unwanted delete can be hours of lost data.

### Cleaning paths

The bare interactive picker is unusable for agents. Use these instead:

```bash
mac-cli clean categories                 # list every category (safe to run anytime — pure inspection)
mac-cli clean config --show              # show effective config (paths, excludes, age thresholds)
mac-cli clean config --init              # write default config to ~/.mac-cli/clean/config.json
mac-cli clean maintenance --dns          # flush DNS (uses sudo — will prompt for password)
mac-cli clean maintenance --purgeable    # thin Time Machine local snapshots
mac-cli clean maintenance --timemachine  # list + delete TM local snapshots
mac-cli clean backup --list              # list pre-delete backups (clean creates these automatically)
mac-cli clean backup --clean             # delete backup sessions older than 7 days
```

### Disk insights (read-only, agent-friendly)

`mac-cli clean insights [path]` prints a one-shot report: the largest folders/files under `path` (default `$HOME`) with proportional bars and percentages, the largest individual files, and a "hidden space" section (iOS backups, old downloads, dev/app caches) tagged *safe to clean* vs *holds real data*. No TTY needed; nothing is deleted.

```bash
mac-cli clean insights                    # analyze $HOME
mac-cli clean insights ~/Library          # analyze a specific folder
mac-cli clean insights ~/Downloads -n 20  # list the top 20 largest files
```

Large folders take a moment (it shells out to `du`). Use it to *find* what to clean, then point the user at the relevant category.

### Live system monitor (read-only, agent-friendly)

`mac-cli clean monitor` shows real-time CPU, memory, disk, network, and power with a 0–100 health score. In a terminal it's a full-screen dashboard refreshing every second (press `q` to quit); under an agent / when piped it prints a single snapshot and exits. Use `--json` for parsing.

```bash
mac-cli clean monitor                     # live dashboard in a terminal; single snapshot if no TTY
mac-cli clean monitor --json              # one machine-readable snapshot (health_score, cpu, memory, disk, network, battery, uptime)
mac-cli clean monitor --json | jq .health_score
```

For uninstalling a Mac app and its leftovers:

```bash
mac-cli clean uninstall --dry-run        # ALWAYS start here — shows what would go
mac-cli clean uninstall --yes            # skip confirmation prompts (after you've verified)
```

Run `--dry-run` first, show the user the list, get explicit confirmation, **restate the action once more right before invoking `--yes`**, and only then run it. Uninstall is 🔴 — see the confirmation policy above; two confirmations are mandatory.

### What about cleaning specific categories non-interactively?

The category-picking flows (`mac-cli clean`, `clean deep`) require a TTY and now **refuse outright without one** — you can't script around them. If the user wants a one-shot cleanup of specific buckets without the picker, tell them to either (a) run it interactively themselves (`mac-cli clean`, or `mac-cli clean deep` to scan everything with safe/moderate pre-checked), or (b) edit `~/.mac-cli/clean/config.json` (see `clean config --show` for the schema) to disable categories they don't want, then run interactively.

As the agent, your read-only path is `clean insights` (find what's using space) and `clean categories` (see what's cleanable) — use those to advise, then hand the actual deletion to the user's interactive session.

> Heads-up on what *does* get deleted now: the file-selection categories (Large Files, Duplicate Files) delete hand-picked files from **anywhere under `$HOME`**, including iCloud Drive (`~/Library/Mobile Documents/…`) — deleting an iCloud file removes it from the cloud across devices. Dev caches (`.cargo/registry`, `.gradle/caches`, `.bundle/cache`, Xcode `DerivedData`) and Electron app caches now actually reclaim space (earlier builds wrongly refused them).

---

## `clop` — image & video pipeline

`clop` is flag-driven and agent-friendly. It picks an operation, optionally a modifier, and a path. If the path is a directory, every supported file inside is processed; add `-r` to recurse.

### Operations (pick exactly one)

| Flag | Operation | Backed by |
|---|---|---|
| `-o`, `--optimise` | Re-encode in place, same format | pngquant / jpegoptim / gifsicle / ffmpeg |
| `-d <factor>`, `--downscale <factor>` | Resize by factor (`0.5` or `50%`) | vipsthumbnail (images) / `ffmpeg -vf scale` (videos) |
| `-c <fmt>`, `--convert <fmt>` | Convert to `webp`, `heic`, or `avif` | cwebp / heif-enc |
| `-s`, `--stripexif` | Strip EXIF, keep orientation | exiftool |

### Modifiers

- `-a`, `--aggressive` — stronger compression, **visible** quality loss. Don't add this by default; only when the user asks for "smallest possible" or accepts quality loss.
- `-r`, `--recursive` — recurse into subdirectories when the path is a directory.
- `-k`, `--keep` — save `<file>.orig` next to each modified file. Use this whenever you're operating on user-supplied originals you can't easily re-fetch.

### Supported extensions

Images: `.png .jpg .jpeg .gif`. Videos: `.mp4 .mov .m4v`. PDFs are currently skipped.

### Tool prerequisites

`clop` shells out. If the tool for a chosen operation is missing, in an interactive context it offers to `brew install` it; in a non-interactive context it declines and fails. Before a large batch, check:

```bash
brew list pngquant jpegoptim gifsicle ffmpeg vips webp libheif exiftool 2>&1 | tail -20
```

The full install command if anything's missing:

```bash
brew install pngquant jpegoptim gifsicle ffmpeg vips webp libheif exiftool
```

### Example invocations

```bash
mac-cli clop -o ~/Pictures/screenshot.png             # single file, in place
mac-cli clop -o ~/Pictures -r                         # whole tree, all supported types
mac-cli clop -d 50% ~/Videos/clip.mp4                 # downscale a video
mac-cli clop -c webp ~/Pictures/cover.png             # convert to webp
mac-cli clop -s ~/Phone/IMG_2156.jpg                  # strip EXIF
mac-cli clop -o -k ~/Pictures/cover.png               # optimise, keep .orig backup
```

### Safety habits

- For destructive-ish operations (`-o`, `-c`, `-s`) on user originals, add `-k` unless the user said not to.
- For `-c`, the original file isn't deleted — a new file with the target extension is written alongside. Confirm with `ls` after running if the user expects in-place replacement.
- Don't combine `-o` with `-a` silently; aggressive mode is a quality decision the user should make.
- Treat `-o` / `-s` on **irreplaceable** originals (phone exports, scans, anything without a second copy) as 🔴 under the confirmation policy above — double-confirm, and add `-k`. `-o` on regenerable assets (build outputs, screenshots in `~/Desktop`) is 🟡 — single confirm.

---

## `shot` — screenshot

Saves PNGs to `~/Desktop`. First invocation on a fresh macOS install will prompt for **Screen Recording** permission in System Settings → Privacy & Security; if it fails silently, that's the cause — tell the user to grant it and retry.

```bash
mac-cli shot -s                # capture the whole screen
mac-cli shot -l                # list running GUI apps: PID  Name
mac-cli shot -p 1234           # capture the app with PID 1234
```

To screenshot "Slack" or "Safari" by name, do it in two steps:

```bash
mac-cli shot -l | grep -i slack         # find the PID
mac-cli shot -p <pid>                   # capture
```

Don't run bare `mac-cli shot` — it opens an interactive filter picker that will hang.

---

## `update` — self-update

```bash
mac-cli update                 # install latest release if newer
mac-cli update --check         # report-only; exits non-zero if an update is available
mac-cli update --force         # reinstall even if already current
```

Environment overrides: `PREFIX=<dir>` to pick an install dir, `VERSION=x.y.z` to pin a specific release.

`update --check` is the safe inspection variant; bare `update` actually downloads and replaces the binary, so confirm with the user before running it unless they explicitly asked to update.

---

## Failure modes worth recognising

- **"command not found: mac-cli"** → not installed, or installed under `~/.local/bin` which isn't on `$PATH`. Check `ls ~/.local/bin/mac-cli` and PATH.
- **A `clop` invocation reports a missing tool** → the corresponding brew formula isn't installed; install it and retry (see the toolchain list above).
- **`shot` produces no file** → Screen Recording permission not granted. Walk the user to System Settings → Privacy & Security → Screen Recording.
- **`clean maintenance --dns` fails** → needs `sudo`; if the user is in a non-interactive shell with no sudoers entry, surface that clearly rather than retrying.
- **`clean` prints "interactive cleanup needs a terminal" and exits** → expected: the destructive scan→clean flows (`clean`, `clean interactive`, `clean deep`) refuse without a TTY. Hand the command to the user; use `clean insights`/`categories` to advise.
- **`clean … ✓ 0 B freed` with `refused (path not safe)` lines** → the path sits outside `$HOME` or in a protected system location (`/System`, `/Applications`, …). This is the allowlist, **not** a permission issue — `sudo` won't change it. (In-`$HOME` caches, large files, and duplicates are *not* refused on current builds.)
- **`clean … system error: /private/var/folders/…`** → those temp dirs are in use by running processes; even root can't delete them mid-session. Harmless; they clear when the owning app quits.
- **Hangs forever with no output** → an interactive prompt waiting on a TTY. On current builds this is `shot` (bare) or a `clop` brew-install prompt — not `clean` (which refuses) or `clean monitor` (which snapshots). Kill the process, switch to the flagged form.

## Things this skill does *not* do

- Run on Intel Macs (the binary is `darwin-arm64` only).
- Process PDFs through `clop` (planned, currently skipped).
- Drive the destructive picker flows (`clean`, `clean interactive`, `clean deep`) or `shot`'s app picker — they need a TTY. Use the non-interactive subcommands (`insights`, `monitor --json`, `categories`, `uninstall --dry-run`, …), or hand the command back to the user.
- Strip language/localization files from apps — that category was removed (breaks code signatures).
