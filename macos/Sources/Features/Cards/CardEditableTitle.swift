import SwiftUI

struct CardEditableTitle: View {
    let title: String
    let field: String
    let commit: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if isEditing {
            TextField(field, text: $draft)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .task {
                    await Task.yield()
                    isFocused = true
                }
                .onSubmit(save)
                .onExitCommand { isEditing = false }
                .onChange(of: isFocused) { focused in
                    if !focused { save() }
                }
        } else {
            Button {
                draft = title
                isEditing = true
            } label: {
                Text(title)
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename " + title)
            .help("Click to rename")
        }
    }

    private func save() {
        guard isEditing else { return }

        isEditing = false

        if draft != title {
            commit(draft)
        }
    }
}
