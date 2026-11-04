import GlassWorkCore
import SwiftUI
import WidgetKit

/// One image from the shared container, or a plain plate while it is missing.
struct WidgetPhotoView: View {
    let data: Data?
    var radius: CGFloat = 12

    /// The picture hangs on an empty view, so the space it gets decides its size and not the other way round.
    var body: some View {
        Color.clear
            .overlay {
                if let data, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "photo").font(.system(size: 20)).foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: radius))
    }
}

/// Text over the bottom of a photo, on a shade that keeps it readable on any picture.
private struct PhotoCaption: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(detail).font(.system(size: 10)).lineLimit(1).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
    }
}

/// Shown until the user turns a widget on, or when macOS took its access away.
struct WidgetTurnOnCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let action: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(tint).widgetAccentable()
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            if !compact {
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 0)
            // The whole widget is the link; this only shows where to click.
            Text(action)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .widgetSolid(Palette.blue, in: .capsule)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Date {
    var longPhotoDate: String {
        formatted(.dateTime.month(.wide).day().year())
    }

    var shortPhotoDate: String {
        formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// Photos from a folder the user chose, one after another.
struct PhotoFrameWidget: View {
    let context: TimeContext

    private var data: PhotoFrameData? {
        context.snapshot.personal?.photoFrame
    }

    private var photos: [WidgetPhoto] {
        data?.photos ?? []
    }

    private var index: Int {
        PhotoRotation.index(at: context.now, count: photos.count)
    }

    private var shown: [WidgetPhoto] {
        photos.rotated(by: index)
    }

    private func image(_ photo: WidgetPhoto?) -> Data? {
        photo.flatMap { context.snapshot.photoImages?[$0.id] }
    }

    private func thumbnail(_ photo: WidgetPhoto) -> Data? {
        context.snapshot.photoImages?[photo.thumbnailID]
    }

    var body: some View {
        if let data {
            switch data.state {
            case .off, .noAccess:
                WidgetTurnOnCard(
                    symbol: "photo",
                    tint: Palette.pink,
                    title: loc("No folder chosen"),
                    detail: loc("Choose a folder in GlassWork. Photos stay on this Mac."),
                    action: loc("Choose…"),
                    compact: context.size == .small
                )
            case .unreadable:
                WidgetEmptyState(
                    symbol: "folder.badge.questionmark",
                    title: loc("The folder cannot be read"),
                    detail: context.size == .small ? nil : data.folderName,
                    tint: Palette.pink
                )
            case .ready where photos.isEmpty:
                WidgetEmptyState(
                    symbol: "photo",
                    title: loc("No photos in \(data.folderName)"),
                    tint: Palette.pink
                )
            case .ready:
                content(data)
            }
        } else {
            WidgetChecking(symbol: "photo", tint: Palette.pink)
        }
    }

    @ViewBuilder
    private func content(_ data: PhotoFrameData) -> some View {
        let current = shown.first
        switch context.size {
        case .small, .medium:
            WidgetPhotoView(data: image(current), radius: 14).overlay(alignment: .bottom) {
                PhotoCaption(title: dateText(current, long: context.size == .medium), detail: place(data, current))
                    .clipShape(.rect(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
            }
        case .large:
            VStack(alignment: .leading, spacing: 6) {
                WidgetPhotoView(data: image(current))
                Text(dateText(current, long: true)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(verbatim: "\(data.folderName) · \(loc("\(index + 1) of \(photos.count)"))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(shown.dropFirst().prefix(5)) { photo in
                        WidgetPhotoView(data: thumbnail(photo), radius: 6)
                    }
                }
                .frame(height: 44)
            }
        case .extraLarge:
            HStack(spacing: 12) {
                WidgetPhotoView(data: image(current))
                VStack(alignment: .leading, spacing: 6) {
                    WidgetCapsTitle(title: loc("Photo Frame"), tint: Palette.pink)
                    Text(dateText(current, long: true)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(current?.name ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Label(data.folderName, systemImage: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(shown.dropFirst().prefix(9)) { photo in
                            WidgetPhotoView(data: thumbnail(photo), radius: 6).frame(height: 62)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(loc("Photos: \(data.total)")).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .frame(width: 210)
            }
        }
    }

    private func dateText(_ photo: WidgetPhoto?, long: Bool) -> String {
        guard let date = photo?.date else { return photo?.name ?? "" }
        return long ? date.longPhotoDate : date.shortPhotoDate
    }

    private func place(_ data: PhotoFrameData, _ photo: WidgetPhoto?) -> String {
        guard context.size == .medium, let name = photo?.name, !name.isEmpty else { return data.folderName }
        return "\(data.folderName) · \(name)"
    }
}

/// The user's own photos taken on this day in past years.
struct OnThisDayWidget: View {
    let context: TimeContext

    private var data: OnThisDayData? {
        context.snapshot.personal?.onThisDay
    }

    private var photos: [WidgetPhoto] {
        data?.photos ?? []
    }

    private var index: Int {
        PhotoRotation.index(at: context.now, count: photos.count)
    }

    private var shown: [WidgetPhoto] {
        photos.rotated(by: index)
    }

    private func image(_ photo: WidgetPhoto?) -> Data? {
        photo.flatMap { context.snapshot.photoImages?[$0.id] }
    }

    private func thumbnail(_ photo: WidgetPhoto) -> Data? {
        context.snapshot.photoImages?[photo.thumbnailID]
    }

    private func year(_ photo: WidgetPhoto?) -> String {
        photo?.date?.formatted(.dateTime.year()) ?? ""
    }

    private func age(_ photo: WidgetPhoto?) -> String {
        guard let date = photo?.date else { return "" }
        return loc("\(OnThisDay.yearsAgo(date, from: context.now)) years ago")
    }

    var body: some View {
        if let data {
            switch data.state {
            case .off, .noAccess, .unreadable:
                WidgetTurnOnCard(
                    symbol: "calendar.badge.clock",
                    tint: Palette.orange,
                    title: data.state == .off ? loc("Your photos from this day") : loc("No access to Photos"),
                    detail: loc("Turn this on in GlassWork. Photos stay on this Mac."),
                    action: loc("Turn On"),
                    compact: context.size == .small
                )
            case .ready where photos.isEmpty:
                WidgetEmptyState(
                    symbol: "calendar.badge.clock",
                    title: loc("No photos from this day"),
                    detail: context.size == .small ? nil : loc("Photos taken today in past years appear here."),
                    tint: Palette.orange
                )
            case .ready:
                content
            }
        } else {
            WidgetChecking(symbol: "calendar.badge.clock", tint: Palette.orange)
        }
    }

    @ViewBuilder
    private var content: some View {
        let current = shown.first
        switch context.size {
        case .small:
            WidgetPhotoView(data: image(current), radius: 14).overlay(alignment: .bottom) {
                PhotoCaption(title: year(current), detail: age(current))
                    .clipShape(.rect(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
            }
        case .medium:
            HStack(spacing: 12) {
                WidgetPhotoView(data: image(current)).frame(width: 190)
                facts(current)
            }
        case .large:
            VStack(alignment: .leading, spacing: 8) {
                header
                WidgetPhotoView(data: image(current))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    yearFigure(current, size: 24)
                    Text(age(current)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(shown.dropFirst().prefix(5)) { photo in
                        WidgetPhotoView(data: thumbnail(photo), radius: 6)
                    }
                }
                .frame(height: 44)
            }
        case .extraLarge:
            HStack(spacing: 14) {
                WidgetPhotoView(data: image(current))
                VStack(alignment: .leading, spacing: 8) {
                    header
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        yearFigure(current, size: 28)
                        Text(age(current)).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Divider()
                    ForEach(shown.dropFirst().prefix(4)) { photo in
                        HStack(spacing: 10) {
                            WidgetPhotoView(data: thumbnail(photo), radius: 6).frame(width: 58, height: 44)
                            yearFigure(photo, size: 15)
                            Text(age(photo)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 230)
            }
        }
    }

    private var header: some View {
        HStack {
            WidgetCapsTitle(title: loc("On This Day"), tint: Palette.orange)
            Spacer(minLength: 6)
            Text(context.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func yearFigure(_ photo: WidgetPhoto?, size: CGFloat) -> some View {
        Text(year(photo))
            .font(.widgetFigure(size))
            .foregroundStyle(Palette.orange)
            .monospacedDigit()
            .widgetAccentable()
    }

    private func facts(_ current: WidgetPhoto?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetCapsTitle(title: loc("On This Day"), tint: Palette.orange)
            yearFigure(current, size: 34)
            Text(age(current)).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(loc("\(index + 1) of \(photos.count)")).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}
