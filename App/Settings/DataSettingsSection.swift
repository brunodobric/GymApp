import Backup
import Models
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// Datoteka za izvoz u "Datoteke" (JSON ili CSV).
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Postavke > Podaci: izvoz, uvoz i brisanje svih podataka.
struct DataSettingsSection: View {
    /// Poziva se nakon brisanja svih podataka, da ekran ponovno dohvati (zadane) postavke.
    let onReset: () -> Void

    @Environment(\.modelContext) private var context

    private enum ExportKind {
        case json, history, body

        var contentType: UTType { self == .json ? .json : .commaSeparatedText }
        var fileExtension: String { self == .json ? "json" : "csv" }
        var baseName: String {
            switch self {
            case .json: "GymApp-sigurnosna-kopija"
            case .history: "GymApp-treninzi"
            case .body: "GymApp-mjerenja"
            }
        }
    }

    @State private var document = BackupDocument()
    @State private var exportType: UTType = .json
    @State private var exportName = "GymApp"
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var showsDeleteStart = false
    @State private var showsDeleteConfirm = false
    @State private var messageTitle: LocalizedStringKey = ""
    @State private var messageText = ""
    @State private var showsMessage = false

    var body: some View {
        Section {
            Button("Izvezi sve podatke (JSON)", systemImage: "square.and.arrow.up") { export(.json) }
            Button("Izvezi treninge (CSV)", systemImage: "tablecells") { export(.history) }
            Button("Izvezi mjerenja tijela (CSV)", systemImage: "tablecells") { export(.body) }
            Button("Uvezi iz datoteke", systemImage: "square.and.arrow.down") { showsImporter = true }
            Button("Obriši sve podatke", systemImage: "trash", role: .destructive) { showsDeleteStart = true }
        } header: {
            Text("Podaci")
        } footer: {
            Text("JSON je puna sigurnosna kopija. CSV datoteke možeš uvesti natrag u aplikaciju. Postojeći zapisi se pri uvozu ne mijenjaju.")
        }
        .fileExporter(
            isPresented: $showsExporter, document: document, contentType: exportType, defaultFilename: exportName
        ) { result in
            if case .failure = result { show("Izvoz nije uspio.", "Datoteka nije spremljena.") }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json, .commaSeparatedText]) { result in
            importFile(result)
        }
        .confirmationDialog("Obriši sve podatke?", isPresented: $showsDeleteStart, titleVisibility: .visible) {
            Button("Prvo izvezi sigurnosnu kopiju") { export(.json) }
            Button("Nastavi s brisanjem", role: .destructive) { showsDeleteConfirm = true }
        } message: {
            Text("Briše sve treninge, predloške, rasporede, vlastite vježbe, mjerenja i postavke s ovog uređaja.")
        }
        .alert("Jesi li siguran?", isPresented: $showsDeleteConfirm) {
            Button("Obriši sve", role: .destructive) { deleteAll() }
            Button("Odustani", role: .cancel) {}
        } message: {
            Text("Ovo se ne može poništiti.")
        }
        .alert(messageTitle, isPresented: $showsMessage) {
            Button("U redu", role: .cancel) {}
        } message: {
            Text(messageText)
        }
    }

    private func show(_ title: LocalizedStringKey, _ text: String) {
        messageTitle = title
        messageText = text
        showsMessage = true
    }

    private func export(_ kind: ExportKind) {
        do {
            let data: Data
            switch kind {
            case .json: data = try JSONBackup.export(from: context)
            case .history: data = Data(try CSVBackup.exportHistory(from: context).utf8)
            case .body: data = Data(try CSVBackup.exportBody(from: context).utf8)
            }
            document = BackupDocument(data: data)
            exportType = kind.contentType
            exportName = "\(kind.baseName)-\(Date.now.formatted(.iso8601.year().month().day()))"
            showsExporter = true
        } catch {
            show("Izvoz nije uspio.", String(localized: "Podaci se nisu mogli pripremiti."))
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let outcome: BackupImportResult
            if url.pathExtension.lowercased() == "json" {
                outcome = try JSONBackup.importBackup(data, into: context)
            } else {
                outcome = try CSVBackup.importAny(String(decoding: data, as: UTF8.self), into: context)
            }
            show("Uvoz je gotov.", String(localized: "Dodano: \(outcome.added). Preskočeno (već postoje): \(outcome.skipped)."))
        } catch BackupError.newerVersion {
            show("Uvoz nije uspio.", String(localized: "Datoteka je iz novije verzije aplikacije."))
        } catch BackupError.invalidCSV(let line) {
            show("Uvoz nije uspio.", String(localized: "CSV nije ispravan (redak \(line)). Ništa nije uvezeno."))
        } catch {
            show("Uvoz nije uspio.", String(localized: "Ovo nije sigurnosna kopija ove aplikacije."))
        }
    }

    private func deleteAll() {
        do {
            try DataReset.deleteAll(in: context)
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            onReset()
            show("Podaci su obrisani.", String(localized: "Aplikacija je vraćena na početno stanje."))
        } catch {
            show("Brisanje nije uspjelo.", String(localized: "Pokušaj ponovno."))
        }
    }
}
