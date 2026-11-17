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
- **If that session's Terminal window is already open, it is brought to the front instead of opening a new one**
- The dot tells you which will happen: green means an open window to focus, grey means a new one
- Hovering a group row reveals a `+` that **starts a new session** in that folder
- **Favourited** sessions gather in a section pinned to the top of the list
- Type part of a title, folder name or branch into the **search field** at the top to filter. ↑↓ to pick, Enter to open
- Right-click to favourite, rename, hide, or move to another group (right-click a group for a new session)
- The list refreshes every 3 seconds

Renaming writes the same record format Claude Code itself uses, so the new name also appears in the `claude --resume` picker and the terminal title. The name does not live in two places.

Sessions you keep returning to go in Favourites. They stay in their real group as well as
appearing at the top — the same arrangement as the Finder sidebar. Inside a group they carry a
small star.

The search field takes input as soon as the popover opens. Every space-separated word must
match, case-insensitively. Matching groups expand on their own, and closing the popover or pressing
Esc clears the search. Conversation content is not searched.

Clearing something out of the list is hiding: no files are touched and it is reversible at any time. The footer's *Show hidden* brings them back into view.

Deleting is available only from that hidden list. Nothing in your working list can be deleted by accident, and reviewing what you hid is the right moment to reclaim space anyway. Deleting moves both the session log and its subagent logs to the Trash. Subagent logs are commonly 10–30× larger than the log itself, so the confirmation shows the combined size.

Moving a session makes the next resume open in that folder. Folders with no sessions yet can be
picked through "Other Folder…". Automatic memory lives per project directory and does not follow
the move; Ferry says how many files stay behind before you commit.

Open windows are matched by tty. A project usually holds several sessions, so the path alone cannot identify a window. Because tty numbers get recycled, the session-leader process on that tty — its pid and start time — is recorded alongside as a fingerprint. Checking costs one sysctl call: no AppleScript, no permission.

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

### Updating

`releases/latest/download` always points at the newest release, so this block works regardless
of which version you have.

```bash
cd ~/Downloads
curl -L -o Ferry.zip https://github.com/noon0ri/ferry/releases/latest/download/Ferry.zip
pkill -x Ferry 2>/dev/null
unzip -o Ferry.zip
rm -rf /Applications/Ferry.app && mv Ferry.app /Applications/
xattr -dr com.apple.quarantine /Applications/Ferry.app
open /Applications/Ferry.app
```

Quitting first matters — replacing the bundle while it runs leaves the old code running until
relaunch. Session names, pending moves and terminal records live in `UserDefaults` keyed by the
bundle identifier, so they survive the update. Session logs are never touched.

macOS may ask for Automation permission again. Ad-hoc signing mints a new signing identity on
every build, and the permission is tied to the signature as well as the bundle identifier.
Being asked again is expected; so is not being asked.

If you built from source, `git pull && ./Scripts/bundle.sh` is enough.

### Launch at login

System Settings → General → Login Items → add Ferry.

## First run

The first time you click a session, macOS asks for permission to control Terminal. Resuming needs it. If you deny, the resume command is copied to your clipboard instead, so you can paste it into a terminal yourself. Change it later under System Settings → Privacy & Security → Automation.

If it asks again after every build, that is expected. `bundle.sh` signs ad-hoc (`--sign -`), and macOS ties Automation permission to the signing identity — a rebuild mints a new identity, which resets the grant.

If the permission dialog never appears and every click just copies to the clipboard, `NSAppleEventsUsageDescription` is missing from the bundle's Info.plist. Check with:

```bash
plutil -extract NSAppleEventsUsageDescription raw build/Ferry.app/Contents/Info.plist
```

## Development

```bash
swift test      # 96 tests
swift build
./Scripts/bundle.sh
```

- `Sources/FerryCore` — logic with no UI: log parsing, directory traversal, command construction, rename, delete
- `Sources/FerryApp` — the menu bar UI
- `Scripts/bundle.sh` — wraps the executable into a `.app`

How Ferry reads the logs, why it parses bytes rather than strings, and how open Terminal
windows are matched — along with everything that went wrong on the way there — is written up
in [handoff.md](handoff.md). Design docs are in [`docs/superpowers/specs/`](docs/superpowers/specs/),
and things deliberately left unfixed are in [`docs/known-issues.md`](docs/known-issues.md).

## License

[MIT](LICENSE)
