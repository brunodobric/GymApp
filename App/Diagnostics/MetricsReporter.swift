import Diagnostics
import Foundation
import MetricKit
import OSLog

/// Prima izvještaje MetricKita (jednom dnevno metrike, a dijagnostike rušenja i zastoja čim ih sustav
/// pripremi) i sprema ih u lokalni dnevnik. Ništa se ne šalje s uređaja: dnevnik se vidi i izvozi u
/// Postavke > O aplikaciji > Dijagnostika, a Appleova izvješća o rušenju stižu u Xcode Organizer
/// samo ako je korisnik to dopustio u postavkama iOS-a.
final class MetricsReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricsReporter()

    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        MXMetricManager.shared.add(self)
        // Izvještaji koji su stigli dok aplikacija nije radila.
        record(metrics: MXMetricManager.shared.pastPayloads)
        record(diagnostics: MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        record(metrics: payloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        record(diagnostics: payloads)
    }

    private func record(metrics payloads: [MXMetricPayload]) {
        let entries = payloads.map { payload in
            DiagnosticEntry(
                receivedAt: Date(), kind: .metrics,
                periodStart: payload.timeStampBegin, periodEnd: payload.timeStampEnd,
                payload: String(decoding: payload.jsonRepresentation(), as: UTF8.self)
            )
        }
        DiagnosticsStore.shared.append(entries)
    }

    private func record(diagnostics payloads: [MXDiagnosticPayload]) {
        let entries = payloads.map { payload in
            let json = payload.jsonRepresentation()
            return DiagnosticEntry(
                receivedAt: Date(), kind: .diagnostics,
                periodStart: payload.timeStampBegin, periodEnd: payload.timeStampEnd,
                counts: MetricKitPayload.diagnosticCounts(from: json),
                payload: String(decoding: json, as: UTF8.self)
            )
        }
        DiagnosticsStore.shared.append(entries)
    }
}

/// Dnevnik dijagnostike u datoteci u Application Support. Ne ide u iCloud ni u sigurnosnu kopiju podataka.
final class DiagnosticsStore: @unchecked Sendable {
    static let shared = DiagnosticsStore()

    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.brunodobric.gymapp", category: "Diagnostics")

    private var fileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Diagnostics.json")
    }

    func load() -> DiagnosticsLog {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }

    func append(_ entries: [DiagnosticEntry]) {
        guard !entries.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var log = read()
        log.append(entries, now: Date())
        write(log)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        write(DiagnosticsLog())
    }

    /// Privremena datoteka za dijeljenje (ShareLink).
    func exportFile() -> URL? {
        let log = load()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Apolon-dijagnostika.json")
        do {
            try log.exportData().write(to: url, options: .atomic)
            return url
        } catch {
            logger.error("Izvoz dijagnostike: \(error.localizedDescription)")
            return nil
        }
    }

    private func read() -> DiagnosticsLog {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return DiagnosticsLog() }
        return (try? DiagnosticsLog.decode(data)) ?? DiagnosticsLog()
    }

    private func write(_ log: DiagnosticsLog) {
        guard let fileURL else { return }
        do {
            var url = fileURL
            try log.encoded().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            logger.error("Spremanje dijagnostike: \(error.localizedDescription)")
        }
    }
}

/// Signposti koje MetricKit mjeri u dnevnim metrikama (trajanje, CPU, memorija po operaciji).
/// Služe za mjerenje performansi u fazi 14: pokretanje, otvaranje treninga, statistika.
enum PerformanceSignpost {
    static let log = MXMetricManager.makeLogHandle(category: "Performanse")

    /// Mjeri sinkroni posao pod danim imenom.
    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        mxSignpost(.begin, log: log, name: name)
        defer { mxSignpost(.end, log: log, name: name) }
        return try work()
    }
}
