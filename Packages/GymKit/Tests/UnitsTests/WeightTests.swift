import Foundation
import Testing
@testable import Units

@Suite("Pretvorba težine")
struct WeightConversionTests {

    @Test("Kilogrami se ne mijenjaju")
    func kilogramsRoundTrip() {
        #expect(WeightConversion.kilograms(from: 82.5, in: .kilograms) == 82.5)
        #expect(WeightConversion.value(fromKilograms: 82.5, in: .kilograms) == 82.5)
    }

    @Test("Unos u funtama sprema se u kilogramima s punom preciznošću")
    func poundsToKilograms() {
        let kg = WeightConversion.kilograms(from: 100, in: .pounds)
        #expect(abs(kg - 45.359237) < 1e-9)
    }

    @Test("Spremljena vrijednost vraća isti prikaz u funtama", arguments: [45.0, 100.0, 135.0, 225.0, 315.0, 405.0])
    func poundsRoundTripDisplay(pounds: Double) {
        let stored = WeightConversion.kilograms(from: pounds, in: .pounds)
        #expect(abs(WeightConversion.displayValue(fromKilograms: stored, in: .pounds) - pounds) < 1e-9)
    }

    @Test("Prikaz se zaokružuje na zadani korak")
    func displayRounding() {
        #expect(abs(WeightConversion.displayValue(fromKilograms: 82.49, in: .kilograms, step: 0.25) - 82.5) < 1e-9)
        #expect(WeightConversion.displayValue(fromKilograms: 82.49, in: .kilograms, step: 0) == 82.49)
    }
}

@Suite("Formatiranje težine")
struct WeightFormatterTests {

    @Test("Hrvatski format koristi decimalni zarez")
    func croatianFormat() {
        let formatter = WeightFormatter(unit: .kilograms, locale: Locale(identifier: "hr_HR"))
        #expect(formatter.string(fromKilograms: 82.5) == "82,5 kg")
        #expect(formatter.string(fromKilograms: 80) == "80 kg")
    }

    @Test("Engleski format u funtama")
    func englishPounds() {
        let formatter = WeightFormatter(unit: .pounds, locale: Locale(identifier: "en_US"))
        let stored = WeightConversion.kilograms(from: 225, in: .pounds)
        #expect(formatter.string(fromKilograms: stored) == "225 lbs")
    }
}
