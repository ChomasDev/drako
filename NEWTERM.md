# newterm

A fork of [Ghostty](https://github.com/ghostty-org/ghostty) (MIT) with a
"card-style" macOS UI. Every pane is still a real Ghostty surface; tabs are
still native NSWindow tabs and splits are Ghostty's split tree. Only the
macOS chrome is restyled.

## Build

```sh
# Zig 0.17.x (brew install zig) + Xcode 26+
zig build -Doptimize=ReleaseFast -Dmetal-runtime-shaders=true
open macos/build/ReleaseLocal/Ghostty.app
```

`-Dmetal-runtime-shaders=true` compiles the Metal shaders at runtime instead of
precompiling a `.metallib`. Use it when the Xcode "Metal Toolchain" component
can't be installed (`xcodebuild -downloadComponent MetalToolchain` fails).

After the first full build, Swift-only changes can be rebuilt faster with:

```sh
cd macos && env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -target Ghostty -configuration ReleaseLocal
```

## What's different

- `macos/Sources/Features/Cards/`: all of the card UI
  - `CardTheme.swift`: colors and metrics (edit this to restyle)
  - `CardTitlebarView.swift`: traffic lights, host label, tab pills, "+"
  - `CardSidebarView.swift`: tabs and panes sidebar (⌘⇧S)
  - `CardPaneView.swift`: pane cards with header buttons, and the window layout
  - `CardChromeModel.swift`: per-window model reading the native tab group
  - `PaneInfo.swift`: foreground program detection (icons) and host info
  - `newterm-defaults.conf`: default theme, loaded *before* the user's Ghostty
    config, so the user's config always wins
- `macos/Sources/Features/Terminal/Window Styles/CardTerminalWindow.swift`:
  the window style. It hides the native titlebar and tab bar.
- The card style is used for `macos-titlebar-style = transparent` (the default)
  and `tabs`. Set `macos-titlebar-style = native` or `hidden` to get the
  original Ghostty look back.
