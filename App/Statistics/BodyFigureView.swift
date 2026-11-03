import Foundation
import Observation
import Stats
import SwiftUI

/// Učitava crteže tijela (MuscleMap, MIT) iz bundlea (`BodyMap/body.json`) i čuva ih zajedno s već pročitanim putanjama.
@MainActor
final class BodyMapStore {
    static let shared = BodyMapStore()

    struct ParsedShape: Identifiable {
        let id: String
        let region: String?
        let commands: [PathCommand]
    }

    struct Parsed {
        let outline: [ParsedShape]
        let muscles: [ParsedShape]
    }

    private var diagrams: [String: BodyMapDiagram]?
    private var cache: [String: Parsed] = [:]

    private func load() -> [String: BodyMapDiagram] {
        if let diagrams { return diagrams }
        let url = Bundle.main.resourceURL?.appendingPathComponent("BodyMap/body.json")
        let loaded = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? BodyMap.decode($0) } ?? [:]
        diagrams = loaded
        return loaded
    }

    func diagram(female: Bool, back: Bool) -> Parsed? {
        let key = BodyMap.key(female: female, back: back)
        if let cached = cache[key] { return cached }
        guard let raw = load()[key] else { return nil }
        func parse(_ shapes: [BodyMapShape]) -> [ParsedShape] {
            shapes.enumerated().map { index, shape in
                ParsedShape(
                    id: "\(shape.id)#\(index)",
                    region: shape.group.flatMap { BodyRegion.region(forBodyMapGroup: $0) },
                    commands: SVGPathParser.parse(shape.d)
                )
            }
        }
        let parsed = Parsed(outline: parse(raw.outline), muscles: parse(raw.muscles))
        cache[key] = parsed
        return parsed
    }
}

/// SwiftUI oblik iz naredbi SVG putanje, skaliran iz vidljivog dijela crteža na zadani pravokutnik.
struct SVGShape: Shape {
    let commands: [PathCommand]

    func path(in rect: CGRect) -> Path {
        let box = BodyMap.visibleBox
        let scaleX = rect.width / box[2]
        let scaleY = rect.height / box[3]
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + (x - box[0]) * scaleX, y: rect.minY + (y - box[1]) * scaleY)
        }
        var path = Path()
        for command in commands {
            switch command {
            case let .move(x, y): path.move(to: point(x, y))
            case let .line(x, y): path.addLine(to: point(x, y))
            case let .curve(c1x, c1y, c2x, c2y, x, y):
                path.addCurve(to: point(x, y), control1: point(c1x, c1y), control2: point(c2x, c2y))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

/// Jedno tijelo (sprijeda ili straga) s mišićima obojenima prema intenzitetu regije.
struct BodyFigureView: View {
    let female: Bool
    let back: Bool
    let heatmap: [String: RegionLoad]
    @Binding var selected: String?

    var body: some View {
        let box = BodyMap.visibleBox
        ZStack {
            if let parsed = BodyMapStore.shared.diagram(female: female, back: back) {
                ForEach(parsed.outline) { shape in
                    SVGShape(commands: shape.commands).fill(Color.secondary.opacity(0.12))
                }
                ForEach(parsed.muscles) { shape in
                    let intensity = shape.region.flatMap { heatmap[$0]?.intensity } ?? 0
                    SVGShape(commands: shape.commands)
                        .fill(intensity > 0 ? Color.accentColor.opacity(0.25 + 0.75 * intensity) : Color.secondary.opacity(0.22))
                        .overlay {
                            if let region = shape.region, region == selected {
                                SVGShape(commands: shape.commands).stroke(Color.primary, lineWidth: 1.5)
                            }
                        }
                        .onTapGesture {
                            if let region = shape.region { selected = selected == region ? nil : region }
                        }
                }
            }
        }
        .aspectRatio(box[2] / box[3], contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
}
