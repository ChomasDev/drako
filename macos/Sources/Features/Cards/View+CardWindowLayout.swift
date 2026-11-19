import SwiftUI

extension View {
    /// Wraps the terminal content in the Drako card chrome when the window has one.
    @ViewBuilder
    func cardWindowLayout(_ chrome: CardChromeModel?) -> some View {
        if let chrome {
            CardWindowLayout(chrome: chrome) { self }
        } else {
            self
        }
    }
}
