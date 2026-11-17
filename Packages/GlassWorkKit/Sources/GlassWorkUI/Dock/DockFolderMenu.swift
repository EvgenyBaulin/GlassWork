import GlassWorkCore
import SwiftUI

public extension FolderSort {
    var title: String {
        switch self {
        case .manual: loc("Manual")
        case .name: loc("Name")
        case .mostUsed: loc("Most Used")
        }
    }
}

/// Right-clicking a folder in the Dock.
struct FolderMenu: View {
    let folder: AppFolder
    let actions: DockActions
    /// Opens a card by item id. The card has the folder's name field, so it also serves to rename.
    let openCard: (String) -> Void

    var body: some View {
        let item = DockItem.folder(folder)
        Button(loc("Open")) { openCard(item.id) }
        Button(loc("Rename…")) { openCard(item.id) }
        Menu(loc("Sort by")) {
            ForEach(FolderSort.allCases, id: \.self) { sort in
                Button {
                    actions.update { DockLayout.sort(folder: folder.id, by: sort, in: $0) }
                } label: {
                    Text(folder.sort == sort ? "✓ \(sort.title)" : sort.title)
                }
            }
        }
        Divider()
        Button(loc("Ungroup")) { actions.update { DockLayout.ungroup(folder, in: $0) } }
        Button(loc("Remove from Dock")) { actions.update { DockLayout.removing(item, from: $0) } }
    }
}

extension FolderTint {
    var colour: Color {
        switch self {
        case .blue: Palette.blue
        case .green: Palette.green
        case .orange: Palette.orange
        case .red: Palette.red
        case .purple: Palette.purple
        case .pink: Palette.pink
        case .teal: Palette.teal
        case .gray: Palette.gray
        }
    }
}

/// Symbol, emoji and colour for a folder's tile, changing it as the choices are made.
struct FolderIconPicker: View {
    let folder: AppFolder
    let actions: DockActions
    @State private var emoji: String

    init(folder: AppFolder, actions: DockActions) {
        self.folder = folder
        self.actions = actions
        _emoji = State(initialValue: folder.emoji ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(FolderSymbols.offered, id: \.self) { symbol in
                    let isChosen = folder.symbol == symbol && folder.emoji == nil
                    Button {
                        emoji = ""
                        set(symbol: symbol, emoji: nil, tint: folder.tint)
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(folder.tint?.colour ?? .primary)
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(isChosen ? 0.28 : 0.1), in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                TextField(loc("Emoji"), text: $emoji)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .onChange(of: emoji) { _, value in
                        let first = String(value.prefix(1))
                        if first != value {
                            emoji = first
                        }
                        set(symbol: folder.symbol, emoji: first, tint: folder.tint)
                    }
                ForEach(FolderTint.allCases, id: \.self) { tint in
                    Button {
                        set(symbol: folder.symbol, emoji: folder.emoji, tint: tint)
                    } label: {
                        Circle()
                            .fill(tint.colour)
                            .frame(width: 18, height: 18)
                            .overlay { Circle().strokeBorder(.white, lineWidth: folder.tint == tint ? 2 : 0) }
                    }
                    .buttonStyle(.plain)
                }
                Button(loc("Reset Icon")) {
                    emoji = ""
                    set(symbol: nil, emoji: nil, tint: nil)
                }
                .font(.system(size: 11))
            }
        }
    }

    private func set(symbol: String?, emoji: String?, tint: FolderTint?) {
        actions.update { DockLayout.setIcon(folder: folder.id, symbol: symbol, emoji: emoji, tint: tint, in: $0) }
    }
}
