import SwiftUI

/// The main window: sections on the left, the chosen one on the right.
public struct MainWindowView<Detail: View>: View {
    @Bindable private var navigation: MainNavigation
    private let openSettings: () -> Void
    private let detail: (MainRoute) -> Detail
    @State private var query = ""

    public init(
        navigation: MainNavigation,
        openSettings: @escaping () -> Void,
        @ViewBuilder detail: @escaping (MainRoute) -> Detail
    ) {
        self.navigation = navigation
        self.openSettings = openSettings
        self.detail = detail
    }

    private var sections: [MainSection] {
        MainSection.allCases.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    /// Choosing Settings hands over to its window, and the list goes back to what was selected.
    private var selection: Binding<MainSection?> {
        Binding(
            get: { navigation.route.section },
            set: { section in
                guard let section else { return }
                if section.opensOwnWindow {
                    openSettings()
                } else {
                    navigation.go(to: MainRoute(section: section))
                }
            }
        )
    }

    public var body: some View {
        NavigationSplitView {
            List(sections, selection: selection) { section in
                MainSidebarRow(section: section).tag(section)
            }
            .searchable(text: $query, placement: .sidebar)
            .navigationSplitViewColumnWidth(220)
        } detail: {
            detail(navigation.route)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(navigation.route.title)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button(loc("Back"), systemImage: "chevron.left") { navigation.goBack() }
                            .disabled(!navigation.canGoBack)
                        Button(loc("Forward"), systemImage: "chevron.right") { navigation.goForward() }
                            .disabled(!navigation.canGoForward)
                    }
                }
        }
    }
}

struct MainSidebarRow: View {
    let section: MainSection

    var body: some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(section.tint.gradient, in: .rect(cornerRadius: 5))
        }
    }
}

/// Heading, one line under it and the content, as every section of the main window starts.
public struct MainSectionPage<Content: View>: View {
    private let heading: String
    private let message: String
    private let content: Content

    public init(heading: String, message: String, @ViewBuilder content: () -> Content) {
        self.heading = heading
        self.message = message
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(heading).font(.system(size: 15, weight: .semibold))
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 2)
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A section that is not built yet.
public struct SectionPlaceholder: View {
    private let section: MainSection
    private let heading: String
    private let note: String
    private let title: String
    private let detail: String?

    public init(
        _ section: MainSection,
        heading: String? = nil,
        note: String? = nil,
        title: String? = nil,
        detail: String? = nil
    ) {
        self.section = section
        self.heading = heading ?? section.title
        self.note = note ?? loc("This section is not ready yet.")
        self.title = title ?? loc("Coming soon")
        self.detail = detail
    }

    public var body: some View {
        MainSectionPage(heading: heading, message: note) {
            VStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(section.tint.gradient, in: .rect(cornerRadius: 11))
                Text(title).font(.system(size: 15, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        }
    }
}
