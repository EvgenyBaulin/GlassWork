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
