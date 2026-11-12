import SwiftUI

extension EnvironmentValues {
    /// True when the terminal view is rendered with the newterm card style.
    @Entry var cardStyle: Bool = false
}

/// Wraps a single Ghostty surface (split pane) in a rounded card with a header row.
///
/// The Metal surface itself is not clipped; instead it is inset inside the card
/// far enough to stay clear of the rounded corners, and the card background is
/// drawn only around it so translucent backgrounds don't stack up.
struct CardPaneView<Content: View>: View {
    @ObservedObject var surfaceView: Ghostty.SurfaceView
    let content: Content

    @EnvironmentObject private var ghostty: Ghostty.App
    @Environment(\.ghosttyLastFocusedSurface) private var lastFocusedSurface

    init(surfaceView: Ghostty.SurfaceView, @ViewBuilder content: () -> Content) {
        self.surfaceView = surfaceView
        self.content = content()
    }

    private var isFocused: Bool {
        lastFocusedSurface?.value === surfaceView
    }

    private var cardFill: Color {
        let bg = surfaceView.backgroundColor ?? ghostty.config.backgroundColor
        return bg.opacity(ghostty.config.backgroundOpacity)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CardTheme.cardRadius, style: .continuous)
        let inset = CardTheme.cardInset

        VStack(spacing: 0) {
            CardPaneHeader(surfaceView: surfaceView, isFocused: isFocused)
                .frame(height: CardTheme.paneHeaderHeight)

            content
                .padding(.horizontal, inset)
                .padding(.bottom, inset)
        }
        .background {
            // Fill the card everywhere except where the surface draws its own background.
            shape
                .fill(cardFill)
                .mask {
                    ZStack {
                        Rectangle()
                        Rectangle()
                            .padding(EdgeInsets(
                                top: CardTheme.paneHeaderHeight,
                                leading: inset,
                                bottom: inset,
                                trailing: inset))
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
        }
        .overlay {
            shape
                .strokeBorder(isFocused ? CardTheme.cardBorderFocused : CardTheme.cardBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

private struct CardPaneHeader: View {
    @ObservedObject var surfaceView: Ghostty.SurfaceView
    let isFocused: Bool

    var body: some View {
        // Foreground process changes aren't observable, so re-sample periodically.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let info = PaneInfo.make(surfaceView)

            HStack(spacing: 7) {
                ProgramIcon(kind: info.kind, size: 11)

                Text(info.program)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isFocused ? CardTheme.primaryText : CardTheme.secondaryText)

                if let cwd = info.cwd {
                    Text(cwd)
                        .font(.system(size: 12))
                        .foregroundStyle(CardTheme.tertiaryText)
                        .truncationMode(.head)
                }

                if info.isRunning {
                    Circle().fill(CardTheme.running).frame(width: 5, height: 5)
                        .help("Running")
                }

                Spacer(minLength: 8)

                HStack(spacing: 1) {
                    PaneButton(symbol: "rectangle.split.2x1", help: "Split Right") {
                        perform("new_split:right")
                    }
                    PaneButton(symbol: "rectangle.split.1x2", help: "Split Down") {
                        perform("new_split:down")
                    }
                    PaneButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Zoom Pane") {
                        perform("toggle_split_zoom")
                    }
                    PaneButton(symbol: "xmark", help: "Close Pane") {
                        perform("close_surface")
                    }
                }
                .opacity(isFocused ? 1 : 0.6)
            }
            .lineLimit(1)
            .padding(.leading, 10)
            .padding(.trailing, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            Ghostty.moveFocus(to: surfaceView)
        }
    }

    private func perform(_ action: String) {
        _ = surfaceView.surfaceModel?.perform(action: action)
    }
}

private struct PaneButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(hovering ? CardTheme.primaryText : CardTheme.secondaryText)
                .frame(width: 22, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Color.white.opacity(0.09) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The overall card window layout: backdrop, titlebar, optional sidebar and
/// the split tree.
struct CardWindowLayout<Content: View>: View {
    @ObservedObject var chrome: CardChromeModel
    let content: Content

    @AppStorage(CardChromeModel.sidebarKey) private var sidebarVisible = false

    init(chrome: CardChromeModel, @ViewBuilder content: () -> Content) {
        self.chrome = chrome
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            CardTitlebarView(chrome: chrome)

            HStack(spacing: CardTheme.gap) {
                if sidebarVisible {
                    CardSidebarView(chrome: chrome)
                }

                content
                    .environment(\.cardStyle, true)
            }
            .padding(.horizontal, CardTheme.gap)
            .padding(.bottom, CardTheme.gap)
        }
        .background(CardTheme.backdrop)
        .ignoresSafeArea()
        .onAppear { chrome.refresh() }
    }
}
