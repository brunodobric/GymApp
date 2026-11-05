import Foundation
import Testing
@testable import Units

@Suite("Unos brojeva i trajanja u poljima")
struct InputParsingTests {
    private let croatian = Locale(identifier: "hr_HR")
    private let english = Locale(identifier: "en_US")

    @Test("Zarez i točka su decimalni znak")
    func decimalSeparators() {
        #expect(NumberInput.parse("82,5", locale: croatian) == 82.5)
        #expect(NumberInput.parse("82.5", locale: english) == 82.5)
        #expect(NumberInput.parse(" 100 ", locale: croatian) == 100)
        #expect(NumberInput.parse("", locale: croatian) == nil)
    }

    @Test("Beskonačno, NaN, negativno i preveliko se odbija", arguments: ["inf", "-inf", "nan", "infinity", "-20", "1e400", "200000"])
    func rejectsInvalid(_ text: String) {
        #expect(NumberInput.parse(text, locale: english) == nil)
        #expect(NumberInput.parse(text, locale: croatian) == nil)
    }

    @Test("Prihvatljiv broj je konačan i između 0 i najvećeg")
    func acceptable() {
        #expect(NumberInput.isAcceptable(0))
        #expect(NumberInput.isAcceptable(NumberInput.maximum))
        #expect(!NumberInput.isAcceptable(-0.5))
        #expect(!NumberInput.isAcceptable(.infinity))
        #expect(!NumberInput.isAcceptable(.nan))
    }

    @Test("Prikaz broja nema više od dvije decimale, a beskonačno je prazno")
    func format() {
        #expect(NumberInput.format(82.5, locale: croatian) == "82,5")
        #expect(NumberInput.format(100, locale: english) == "100")
        #expect(NumberInput.format(nil) == "")
        #expect(NumberInput.format(.infinity) == "")
    }

    @Test("Trajanje u sekundama, minutama i satima")
    func durations() {
        #expect(DurationInput.parse("90") == 90)
        #expect(DurationInput.parse("1:30") == 90)
        #expect(DurationInput.parse("1:00:05") == 3605)
        #expect(DurationInput.parse("") == nil)
    }

    @Test("Neispravno ili predugo trajanje se odbija", arguments: ["-5", "1:-30", "1:2:3:4", "abc", "1:", "9999999999999999999", "99999999:00"])
    func rejectsInvalidDurations(_ text: String) {
        #expect(DurationInput.parse(text) == nil)
    }

    @Test("Prikaz trajanja")
    func durationFormat() {
        #expect(DurationInput.format(90) == "1:30")
        #expect(DurationInput.format(3605) == "1:00:05")
        #expect(DurationInput.format(nil) == "")
    }
}
