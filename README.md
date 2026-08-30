# Ferry

**English** · [한국어](README.ko.md)

A macOS menu bar app that gathers your scattered Claude Code sessions into one list and reopens any of them with a click.

## Why

Claude Code sessions are scattered across project folders. `claude --resume` only lists sessions in the current directory, and that list shows UUIDs and timestamps — not what the conversation was about.

So you stop closing terminal windows. Even a session you return to once a week stays open, because finding it again is a chore. Ferry exists so those windows can be closed.

## What it does

- Shows every session under `~/.claude/projects/`, grouped by working directory
- Session titles come from what is already recorded in the log, so you see "Build an interactive 3D icon set" rather than a UUID
- Clicking one opens Terminal in that folder and runs `claude --resume`
- Sessions active within the last 60 seconds get a green dot; the list refreshes every 3 seconds
- Right-click to rename or delete

Renaming writes the same record format Claude Code itself uses, so the new name also appears in the `claude --resume` picker and the terminal title. The name does not live in two places.

Deleting moves both the session log and its subagent logs to the Trash. Subagent logs are commonly 10–30× larger than the log itself, so the confirmation shows the combined size.

## Requirements

macOS 14 or later. Universal binary — runs on both Intel and Apple Silicon.

## Install

### Download (no Xcode needed)

Grab `Ferry.zip` from [Releases](https://github.com/noon0ri/ferry/releases). It uses only system frameworks, so there is nothing else to install.

```bash
cd ~/Downloads && unzip Ferry.zip
mv Ferry.app /Applications/

# Gatekeeper blocks apps downloaded from the internet. This clears it.
xattr -d com.apple.quarantine /Applications/Ferry.app

open /Applications/Ferry.app
```

If you would rather not use Terminal: right-click the app in Finder → Open → Open again.

Gatekeeper blocks it because the app is ad-hoc signed, so the developer cannot be verified. Notarizing with a paid developer account would remove this step; it is a personal tool, so it is not notarized.

### Build from source

```bash
git clone https://github.com/noon0ri/ferry.git
cd ferry
./Scripts/bundle.sh
cp -R build/Ferry.app /Applications/
```

Requires Xcode 26 or later (Swift 6.3). A locally built app carries no quarantine attribute, so the `xattr` step above is unnecessary. To update: `git pull && ./Scripts/bundle.sh`.

### Launch at login

System Settings → General → Login Items → add Ferry.

## First run

The first time you click a session, macOS asks for permission to control Terminal. Resuming needs it. If you deny, the resume command is copied to your clipboard instead, so you can paste it into a terminal yourself. Change it later under System Settings → Privacy & Security → Automation.

If it asks again after every build, that is expected. `bundle.sh` signs ad-hoc (`--sign -`), and macOS ties Automation permission to the signing identity — a rebuild mints a new identity, which resets the grant.

If the permission dialog never appears and every click just copies to the clipboard, `NSAppleEventsUsageDescription` is missing from the bundle's Info.plist. Check with:

```bash
plutil -extract NSAppleEventsUsageDescription raw build/Ferry.app/Contents/Info.plist
```

## How it works

Ferry reads the session logs under `~/.claude/projects/`. **It writes in exactly two places** — renaming (appends one line to the log) and deleting (moves to the Trash). Nothing else is touched.

Session logs are JSON Lines. Ferry needs four things from them: the user-set name (`custom-title`), the auto-generated title (`ai-title`), the working directory (`cwd`), and the git branch.

Two facts drive the performance work.

**Log files exceed 20 MB.** Reading them whole on every popover open is not viable, so Ferry reads only the last 256 KB. Title records are rewritten repeatedly during a session and therefore sit near the end of the file; only when the tail does not yield one does Ferry fall back to reading the whole file.

**Do not turn that tail into a Swift `String`.** Converting 256 KB to a string and calling `split` accounts for more than half of total scan time (measured: split alone ~94 ms across 23 files) — the cost of grapheme-cluster-aware processing. Ferry works over `Data` bytes and parses only the lines it needs.

The grouping key is the `cwd` value from inside the log. Directory names (`-Users-me-Codes-my-project`) cannot be decoded back into paths: there is no way to tell whether a hyphen is a path separator or part of a folder name, and folder names with spaces are common.

Measured with 23 sessions: 92 ms for the first scan, 1 ms after that. Only files whose mtime changed are re-read.

## Development

```bash
swift test      # 49 tests
swift build
swift run FerryApp
```

- `Sources/FerryCore` — logic with no UI: log parsing, directory traversal, command construction, rename, delete
- `Sources/FerryApp` — the menu bar UI
- `Scripts/bundle.sh` — wraps the executable into a `.app`

Design rationale lives in [`docs/superpowers/specs/`](docs/superpowers/specs/). Things deliberately left unfixed, and why, are in [`docs/known-issues.md`](docs/known-issues.md).

## License

[MIT](LICENSE)
