import Foundation

/// Tekst licence za prikaz na ekranu O aplikaciji.
public enum LicenseText {
    /// Tvrdi prijelomi unutar odlomaka se spajaju da tekst teče po širini ekrana. Prazni redovi
    /// i stavke koje počinju s "- " ostaju zasebni odlomci.
    public static func reflowed(_ raw: String) -> String {
        var paragraphs: [String] = []
        var current = ""
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.hasPrefix("- ") {
                if !current.isEmpty { paragraphs.append(current) }
                current = text
            } else {
                current += current.isEmpty ? text : " " + text
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.joined(separator: "\n\n")
    }
}
