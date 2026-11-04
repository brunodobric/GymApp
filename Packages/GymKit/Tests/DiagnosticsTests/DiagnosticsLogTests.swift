import Diagnostics
import Foundation
import Testing

struct DiagnosticsLogTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(daysAgo: Double, counts: [String: Int] = [:]) -> DiagnosticEntry {
        DiagnosticEntry(
            receivedAt: now.addingTimeInterval(-daysAgo * 86_400),
            kind: counts.isEmpty ? .metrics : .diagnostics,
            counts: counts,
            payload: #"{"daysAgo":\#(daysAgo)}"#
        )
    }

    @Test func najnovijiPrvi() {
        var log = DiagnosticsLog()
        log.append([entry(daysAgo: 3), entry(daysAgo: 1), entry(daysAgo: 2)], now: now)
        #expect(log.entries.map(\.receivedAt) == [1.0, 2, 3].map { now.addingTimeInterval(-$0 * 86_400) })
    }

    @Test func staroIspada() {
        var log = DiagnosticsLog()
        log.append([entry(daysAgo: 10), entry(daysAgo: 91)], now: now)
        #expect(log.entries.count == 1)
    }

    @Test func najviseTridesetIzvjestaja() {
        var log = DiagnosticsLog()
        log.append((0..<40).map { entry(daysAgo: Double($0)) }, now: now)
        #expect(log.entries.count == DiagnosticsLog.maxEntries)
        #expect(log.entries.first?.receivedAt == now)
    }

    @Test func istiIzvjestajSeNeDuplira() {
        var log = DiagnosticsLog()
        log.append([entry(daysAgo: 1)], now: now)
        // Isti JSON stigne ponovno pri sljedećem pokretanju, s novim id-em.
        log.append([entry(daysAgo: 1)], now: now)
        #expect(log.entries.count == 1)
    }

    @Test func zbrojPoVrsti() {
        var log = DiagnosticsLog()
        log.append([entry(daysAgo: 1, counts: ["crash": 1, "hang": 2]), entry(daysAgo: 2, counts: ["hang": 1])], now: now)
        #expect(log.totals == ["crash": 1, "hang": 3])
        #expect(log.entries.first?.totalCount == 3)
    }

    @Test func spremanjeIUcitavanje() throws {
        var log = DiagnosticsLog()
        log.append([entry(daysAgo: 1, counts: ["crash": 1])], now: now)
        let decoded = try DiagnosticsLog.decode(log.encoded())
        #expect(decoded == log)
    }

    @Test func izvozSadrziIzvorniJSON() throws {
        var log = DiagnosticsLog()
        log.append([DiagnosticEntry(receivedAt: now, kind: .diagnostics, counts: ["crash": 1], payload: #"{"a":1}"#)], now: now)
        let items = try #require(JSONSerialization.jsonObject(with: log.exportData()) as? [[String: Any]])
        #expect(items.count == 1)
        #expect((items[0]["payload"] as? [String: Int]) == ["a": 1])
        #expect(items[0]["kind"] as? String == "diagnostics")
    }

    @Test func brisanje() {
        var log = DiagnosticsLog()
        log.append([entry(daysAgo: 1)], now: now)
        log.removeAll()
        #expect(log.entries.isEmpty)
    }
}

struct MetricKitPayloadTests {
    private let sample = Data("""
    {
      "timeStampBegin": "2026-11-03 00:00:00 +0000",
      "timeStampEnd": "2026-11-04 00:00:00 +0000",
      "crashDiagnostics": [{}, {}],
      "hangDiagnostics": [{}],
      "cpuExceptionDiagnostics": [],
      "metaData": {"appVersion": "0.1.0"}
    }
    """.utf8)

    @Test func brojiDijagnostike() {
        #expect(MetricKitPayload.diagnosticCounts(from: sample) == ["crash": 2, "hang": 1])
    }

    @Test func razdoblje() {
        let period = MetricKitPayload.period(from: sample)
        #expect(period.start == Date(timeIntervalSince1970: 1_793_664_000))
        #expect(period.end == Date(timeIntervalSince1970: 1_793_750_400))
    }

    @Test func neispravanJSON() {
        #expect(MetricKitPayload.diagnosticCounts(from: Data("nije json".utf8)).isEmpty)
        #expect(MetricKitPayload.period(from: Data()).start == nil)
    }
}
