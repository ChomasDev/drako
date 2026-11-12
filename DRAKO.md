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

- Every tab belongs to one host and has a stable drako tab key (8 hex chars);
  the UI shows the pane's program and folder instead.
- **New tab** (`+`, ⌘T): pick the host from a menu (the last used one is
  checked). It runs `drako new --tab <key>` and opens a pane running
  `drako attach <id>`, or `ssh -t <host> /usr/local/bin/drako attach <id>`.
- **Split**: a new session in the same drako tab.
- **Close** a pane (card ×, ⌘W) or a tab: `drako kill`. A pane whose program
  already ended (shell `exit`, ctrl+\ detach) is left alone.
- **Quit** Drako: nothing is killed. On launch, `drako ls --json` on every host
  rebuilds the tabs (panes side by side: layouts aren't stored).
- **Move**: right-click a card header → Move to Tab ▸ (tabs of the same host,
  or New Tab). Runs `drako move <id> <key>` and re-attaches the pane there.
- **Disconnected**: when ssh drops, the card says "Disconnected · Reconnect";
  click it or press Enter in the pane to re-attach.
- **Sidebar** (⌘⇧S): hosts with reachability (green / grey), their tabs, panes.

## Config

Drako reads your Ghostty config (keybindings, fonts, ...) with two bundled
files around it:

- `drako-defaults.conf`, loaded *before* your config: the neutral charcoal
  theme with small pastel accents and card-friendly defaults. Anything you set explicitly wins.
- `drako-overrides.conf`, loaded *after* it: only `theme =`, so a Ghostty
  `theme` doesn't hide the Drako colors.

## Code

- `macos/Sources/Features/Drako/`: hosts, the `drako` CLI runner and the store
  tying tabs/panes to sessions
- `macos/Sources/Features/Cards/`: the card UI
  - `CardTheme.swift`: colors and metrics (edit this to restyle)
  - `CardTitlebarView.swift`: traffic lights, host label, tab pills, "+" menu
  - `CardSidebarView.swift`: hosts → tabs → panes sidebar (⌘⇧S)
  - `CardPaneView.swift`: pane cards (header buttons, move menu, disconnected badge)
  - `CardChromeModel.swift`: per-window model reading the native tab group
  - `PaneInfo.swift`: foreground program detection (icons) and host info
- `macos/Sources/Features/Terminal/Window Styles/CardTerminalWindow.swift`:
  the window style. It hides the native titlebar and tab bar.
- The card style is used for `macos-titlebar-style = transparent` (the default)
  and `tabs`. Set `macos-titlebar-style = native` or `hidden` to get the
  original Ghostty look back.
