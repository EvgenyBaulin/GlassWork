import AppKit
import Contacts
import GlassWorkCore
import ImageIO
import Photos

/// The real Photos library. Only the app links this: the extension never sees the library.
struct SystemPhotoLibrary: PhotoLibraryReading {
    func access() -> PersonalAccess {
        Self.access(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAccess() async -> PersonalAccess {
        await Self.access(PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    private static func access(_ status: PHAuthorizationStatus) -> PersonalAccess {
        switch status {
        case .authorized, .limited: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    func photos(onThisDay date: Date, limit: Int) async -> [ReadPhoto] {
        let days = OnThisDay.days(before: date)
        guard access() == .granted, !days.isEmpty else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: days.map {
            NSPredicate(format: "creationDate >= %@ AND creationDate < %@", $0.start as NSDate, $0.end as NSDate)
        })
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var photos: [ReadPhoto] = []
        assets.enumerateObjects { asset, _, stop in
            guard !asset.mediaSubtypes.contains(.photoScreenshot) else { return }
            if let photo = Self.photo(asset) {
                photos.append(photo)
            }
            if photos.count >= limit {
                stop.pointee = true
            }
        }
        return photos
    }

    private static func photo(_ asset: PHAsset) -> ReadPhoto? {
        guard let image = jpeg(asset, pixels: ReadPhoto.imagePixels),
              let thumbnail = jpeg(asset, pixels: ReadPhoto.thumbnailPixels) else { return nil }
        return ReadPhoto(date: asset.creationDate, name: "", image: image, thumbnail: thumbnail)
    }

    /// Only what is already on this Mac: a photo kept in iCloud is skipped rather than downloaded.
    private static func jpeg(_ asset: PHAsset, pixels: Int) -> Data? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        var result: Data?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: pixels, height: pixels),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            result = image.flatMap(jpeg)
        }
        return result
    }

    private static func jpeg(_ image: NSImage) -> Data? {
        guard let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: picture).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}

/// The real Contacts. Only names and birthdays are ever fetched.
struct SystemBirthdays: BirthdayReading {
    func access() -> PersonalAccess {
        Self.access(CNContactStore.authorizationStatus(for: .contacts))
    }

    func requestAccess() async -> PersonalAccess {
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        return access()
    }

    private static func access(_ status: CNAuthorizationStatus) -> PersonalAccess {
        switch status {
        case .authorized, .limited: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    func birthdays() async -> [ContactBirthday] {
        guard access() == .granted else { return [] }
        let keys: [any CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactBirthdayKey as CNKeyDescriptor,
        ]
        var found: [ContactBirthday] = []
        try? CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
            guard let birthday = contact.birthday else { return }
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            if !name.isEmpty, let item = ContactBirthday(id: contact.identifier, name: name, components: birthday) {
                found.append(item)
            }
        }
        return found
    }
}
