import Testing
@testable import Stats

@Suite("Raspon osi Y grafa")
struct ChartValueDomainTests {
    @Test func equalValuesGetARange() {
        let domain = ChartValueDomain.domain(for: [14, 14, 14])
        #expect(domain.lowerBound < 14)
        #expect(domain.upperBound > 14)
        #expect(abs(domain.lowerBound - 12.6) < 1e-9)
        #expect(abs(domain.upperBound - 15.4) < 1e-9)
    }

    @Test func smallEqualValuesGetAtLeastOneUnitAndStayAboveZero() {
        let domain = ChartValueDomain.domain(for: [0.5, 0.5])
        #expect(domain.lowerBound == 0)
        #expect(domain.upperBound == 1.5)
        #expect(ChartValueDomain.domain(for: [0]) == 0...1)
    }

    @Test func differentValuesArePadded() {
        let domain = ChartValueDomain.domain(for: [10, 40, 20])
        #expect(abs(domain.lowerBound - 7) < 1e-9)
        #expect(abs(domain.upperBound - 43) < 1e-9)
    }

    @Test func positiveValuesNeverGoBelowZero() {
        #expect(ChartValueDomain.domain(for: [1, 100]).lowerBound == 0)
    }

    @Test func emptyHasDefaultRange() {
        #expect(ChartValueDomain.domain(for: []) == 0...1)
        #expect(ChartValueDomain.domain(for: [.nan]) == 0...1)
    }
}
