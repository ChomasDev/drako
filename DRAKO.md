# Drako

A fork of [Ghostty](https://github.com/ghostty-org/ghostty) (MIT) with a
"card-style" macOS UI where every pane is a **drako session**: a native
terminal (PTY + headless libghostty-vt, via zmx) that survives the app.
Quitting Drako or losing the network only detaches; relaunching re-attaches
every tab with its screen and scrollback.

The session server lives in a separate repo (branch `drako-server`).

## Build

```sh
# Zig 0.17.x (brew install zig) + Xcode 26+
zig build -Doptimize=ReleaseFast -Dmetal-runtime-shaders=true
open macos/build/ReleaseLocal/Drako.app
```

`-Dmetal-runtime-shaders=true` compiles the Metal shaders at runtime instead of
precompiling a `.metallib`. Use it when the Xcode "Metal Toolchain" component
can't be installed (`xcodebuild -downloadComponent MetalToolchain` fails).

After the first full build, Swift-only changes can be rebuilt faster with:

```sh
cd macos && env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -target Ghostty -configuration ReleaseLocal
```

The app is `Drako.app`, bundle id `dev.drako.Drako`: its preferences and saved
windows are separate from Ghostty's.

## The drako server

On this Mac:

```sh
git clone -b drako-server villafavero@villafavero:/home/villafavero/.t3/projects/newterm ~/Project/drako-server
cd ~/Project/drako-server
zig build -Doptimize=ReleaseSafe && zig build test
install -m 755 zig-out/bin/drako /opt/homebrew/bin/drako   # or ~/.local/bin/drako
```

Drako looks for the local binary in `/opt/homebrew/bin`, `~/.local/bin` and
`/usr/local/bin`. On remote hosts it runs `/usr/local/bin/drako`.

## Hosts

"This Mac" is always there. Remote hosts are ssh targets, one per line, in
`~/.config/drako/hosts` (blank lines and `#` comments are skipped):

```
villafavero@villafavero
```

The Mac must reach them with key auth (`ssh -o BatchMode=yes <target> true`).
Drako shares one ssh connection per host (`ControlPath=~/.ssh/drako-%C`,
`ControlPersist=10m`), so extra panes open fast.

## How tabs map to sessions

- A pane is a drako terminal on one host: `(host, id)`. Tabs belong to the
  client, so one tab can mix machines (a local pane next to a remote one).
- The workspace (tabs, order, titles, the panes of each tab and their split
  layout) is saved on this Mac in
  `~/Library/Application Support/Drako/workspace.json`. On launch Drako
  rebuilds it, dropping the panes whose terminal is gone; panes of a host that
  can't be reached are kept and reconnect on Enter. The very first launch
  groups the live terminals by their drako tab key instead.
- `drako ls --json` on each host only checks which terminals are alive and
  finds **detached** ones (live, but in no tab). `--tab <key>` is still passed
  to `drako new` and `drako move` as a hint, but never used to group panes.
- **New tab** (`+`, ⌘T): on the last used host. Hold the `+` for the host menu.
- **Split**: on the focused pane's host. ⌥-click a split button, or use the
  small chevron next to them, to pick another machine.
- **Machines** (the host name in the titlebar, showing the focused pane's
  host): every machine with status, live terminals and latency, "New terminal
  here" (a pane on that host in the current tab) and "Edit hosts…".
- **Close** a pane (card ×, ⌘W) or a tab: `drako kill`. A pane whose program
  already ended (shell `exit`, ctrl+\ detach) is left alone.
- **Quit** Drako: nothing is killed.
- **Move** a pane to another tab: drag it in the sidebar, or right-click a card
  header → Move to Tab ▸. The pane moves as is (no re-attach).
- **Disconnected**: when ssh drops, the card says "disconnected · reconnect";
  click it or press Enter in the pane to re-attach.
- **Sidebar** (⌘⇧S): Machines, Tabs (with their panes, collapsible) and
  Detached. Drag tabs to reorder them, a pane onto a tab to move it or onto a
  pane of the same tab to swap them, a detached terminal onto a tab to attach
  it (or click it to attach it to the current tab).

## Config

Drako reads your Ghostty config (keybindings, fonts, ...) with two bundled
files around it:

- `drako-defaults.conf`, loaded *before* your config: the neutral charcoal
  theme with small pastel accents and card-friendly defaults. Anything you set explicitly wins.
- `drako-overrides.conf`, loaded *after* it: only `theme =`, so a Ghostty
  `theme` doesn't hide the Drako colors.

## Code

- `macos/Sources/Features/Drako/`: hosts, the `drako` CLI runner, the saved
  workspace and the store tying tabs/panes to sessions
- `macos/Sources/Features/Cards/`: the card UI
  - `CardTheme.swift`: colors and metrics (edit this to restyle)
  - `CardTitlebarView.swift`: traffic lights, host label, tab pills, "+" menu
  - `CardSidebarView.swift`: machines / tabs → panes / detached sidebar (⌘⇧S)
  - `CardPaneView.swift`: pane cards (header buttons, move menu, disconnected badge)
  - `CardChromeModel.swift`: `CardWorkspace`, the one model of tabs, panes and
    detached terminals behind the titlebar and sidebar, and the per-window handle
  - `PaneInfo.swift`: foreground program detection (icons) and host info
- `macos/Sources/Features/Terminal/Window Styles/CardTerminalWindow.swift`:
  the window style. It hides the native titlebar and tab bar.
- The card style is used for `macos-titlebar-style = transparent` (the default)
  and `tabs`. Set `macos-titlebar-style = native` or `hidden` to get the
  original Ghostty look back.
