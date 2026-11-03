import SwiftUI
import UIKit

/// Sličica vježbe za mrežu kataloga. Slika se umanjuje izvan glavne niti i pamti u memoriji,
/// pa brzo pomicanje mreže sa stotinama vježbi ne zastajkuje.
struct ExerciseThumbnail: View {
    enum Source: Hashable, Sendable {
        /// Slika službene vježbe iz bundlea.
        case file(URL)
        /// Fotografija vlastite vježbe iz baze. Uspoređuje se po ključu (id vježbe) i veličini,
        /// da se pri svakom iscrtavanju ne uspoređuju cijeli podaci slike.
        case data(key: String, Data)

        static func == (lhs: Source, rhs: Source) -> Bool {
            switch (lhs, rhs) {
            case let (.file(left), .file(right)): left == right
            case let (.data(leftKey, left), .data(rightKey, right)): leftKey == rightKey && left.count == right.count
            default: false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case .file(let url): hasher.combine(url)
            case .data(let key, let data):
                hasher.combine(key)
                hasher.combine(data.count)
            }
        }
    }

    let source: Source?

    @State private var image: UIImage?

    var body: some View {
        Color(.tertiarySystemFill)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "dumbbell")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
            .task(id: source) {
                image = nil
                guard let source else { return }
                image = await ThumbnailLoader.image(for: source)
            }
    }
}

/// Učitavanje i umanjivanje sličica, s predmemorijom.
@MainActor
enum ThumbnailLoader {
    private static let cache = NSCache<NSString, UIImage>()

    /// Najveća strana sličice u pikselima (dovoljno za ćeliju na iPadu u Retina rezoluciji).
    private static let maxPixelSize: CGFloat = 480

    static func image(for source: ExerciseThumbnail.Source) async -> UIImage? {
        let key = cacheKey(for: source)
        if let cached = cache.object(forKey: key) { return cached }
        let maxSize = maxPixelSize
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            let original: UIImage?
            switch source {
            case .file(let url): original = UIImage(contentsOfFile: url.path)
            case .data(_, let data): original = UIImage(data: data)
            }
            guard let original else { return nil }
            let scale = min(1, maxSize / max(original.size.width, original.size.height, 1))
            let size = CGSize(width: original.size.width * scale, height: original.size.height * scale)
            return original.preparingThumbnail(of: size) ?? original
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    private static func cacheKey(for source: ExerciseThumbnail.Source) -> NSString {
        switch source {
        case .file(let url): url.path as NSString
        case .data(let key, let data): "\(key)-\(data.count)" as NSString
        }
    }
}
