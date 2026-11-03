import Foundation

/// Naredba SVG putanje. MuscleMap koristi samo apsolutne naredbe M, L, C i Z.
public enum PathCommand: Equatable, Sendable {
    case move(toX: Double, toY: Double)
    case line(toX: Double, toY: Double)
    case curve(c1x: Double, c1y: Double, c2x: Double, c2y: Double, toX: Double, toY: Double)
    case close
}

/// Čita SVG podatke putanje (`d`) u naredbe. Podržane su apsolutne M, L, C i Z, s ponavljanjem argumenata
/// (npr. "C a b c d e f g h i j k l"). Nepoznata naredba ili nepotpuni argumenti prekidaju čitanje te putanje.
public enum SVGPathParser {
    private enum Token {
        case command(Character)
        case number(Double)
    }

    public static func parse(_ data: String) -> [PathCommand] {
        let tokens = tokenize(data)
        var commands: [PathCommand] = []
        var index = 0
        var current: Character?

        func numbers(_ count: Int) -> [Double]? {
            var result: [Double] = []
            var cursor = index
            while result.count < count, cursor < tokens.count, case .number(let value) = tokens[cursor] {
                result.append(value)
                cursor += 1
            }
            guard result.count == count else { return nil }
            index = cursor
            return result
        }

        while index < tokens.count {
            if case .command(let letter) = tokens[index] {
                current = letter
                index += 1
                if letter == "Z" || letter == "z" {
                    commands.append(.close)
                    continue
                }
            }
            guard let letter = current else { return commands }
            switch letter {
            case "M":
                guard let values = numbers(2) else { return commands }
                commands.append(.move(toX: values[0], toY: values[1]))
                current = "L" // dodatni parovi iza M su linije
            case "L":
                guard let values = numbers(2) else { return commands }
                commands.append(.line(toX: values[0], toY: values[1]))
            case "C":
                guard let values = numbers(6) else { return commands }
                commands.append(.curve(c1x: values[0], c1y: values[1], c2x: values[2], c2y: values[3], toX: values[4], toY: values[5]))
            default:
                return commands
            }
        }
        return commands
    }

    private static func tokenize(_ data: String) -> [Token] {
        var tokens: [Token] = []
        var number = ""
        var hasDot = false

        func flush() {
            if !number.isEmpty, let value = Double(number) { tokens.append(.number(value)) }
            number = ""
            hasDot = false
        }

        for character in data {
            switch character {
            case "0"..."9":
                number.append(character)
            case ".":
                if hasDot { flush() }
                hasDot = true
                number.append(character)
            case "-":
                flush()
                number.append(character)
            case " ", ",", "\n", "\t":
                flush()
            default:
                flush()
                tokens.append(.command(character))
            }
        }
        flush()
        return tokens
    }
}

/// Jedan crtež iz MuscleMap resursa (obris tijela ili jedna mišićna ploha).
public struct BodyMapShape: Codable, Equatable, Sendable {
    public let id: String
    /// Grupa mišića u MuscleMap nazivlju (npr. "QUADS"). Obris tijela je nema.
    public let group: String?
    public let pathData: String

    private enum CodingKeys: String, CodingKey {
        case id, group
        case pathData = "d"
    }
}

/// Tijelo jednog spola i strane (sprijeda ili straga) s obrisom i mišićnim plohama.
public struct BodyMapDiagram: Codable, Equatable, Sendable {
    public let viewBox: [Double]
    /// Vidljivi dio crteža (x, y, širina, visina). Prednja i stražnja strana istog spola imaju isti okvir.
    public let bounds: [Double]
    public let outline: [BodyMapShape]
    public let muscles: [BodyMapShape]
}

public enum BodyMap {
    public static func key(female: Bool, back: Bool) -> String {
        "\(female ? "female" : "male")-\(back ? "back" : "front")"
    }

    public static func decode(_ data: Data) throws -> [String: BodyMapDiagram] {
        try JSONDecoder().decode([String: BodyMapDiagram].self, from: data)
    }
}

extension BodyRegion {
    /// Regija heatmapa za grupu mišića iz MuscleMap crteža. Nil za nepoznatu grupu.
    public static func region(forBodyMapGroup group: String) -> String? {
        switch group {
        case "CHEST": "chest"
        case "SHOULDERS_FRONT", "SHOULDERS_SIDE", "SHOULDERS_REAR": "shoulders"
        case "BICEPS": "biceps"
        case "TRICEPS": "triceps"
        case "FOREARMS": "forearms"
        case "CORE", "OBLIQUES": "abs"
        case "QUADS": "quads"
        case "HAMSTRINGS": "hamstrings"
        case "ADDUCTORS": "innerThigh"
        case "ABDUCTORS": "outerThigh"
        case "TRAPEZIUS": "traps"
        case "RHOMBOIDS": "upperBack"
        case "LATS": "lats"
        case "BACK_LOWER": "lowerBack"
        case "GLUTES": "glutes"
        case "CALVES": "calves"
        default: nil
        }
    }
}
