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

/// Stanje Postavke > Podaci, zajedničko retcima i prozorima koji se iz njih otvaraju.
@MainActor
@Observable
final class DataSettingsModel {
    enum ExportKind {
        case json, history, body

        var contentType: UTType { self == .json ? .json : .commaSeparatedText }
        var baseName: String {
            switch self {
            case .json: "Apolon-sigurnosna-kopija"
            case .history: "Apolon-treninzi"
            case .body: "Apolon-mjerenja"
            }
        }
    }

    /// Pregled uvoza iz druge aplikacije, za `.sheet(item:)`.
    struct ForeignImportRequest: Identifiable {
        let id = UUID()
        let preview: ForeignWorkoutImport.Preview
    }

    var document = BackupDocument()
    var exportType: UTType = .json
    var exportName = "Apolon"
    var showsExporter = false
    var showsImporter = false
    var showsDeleteStart = false
    var showsDeleteConfirm = false
    var messageTitle: LocalizedStringKey = ""
    var messageText = ""
    var showsMessage = false
    var isDeleting = false
    var foreignImport: ForeignImportRequest?
    /// Potvrđeni uvoz: pokreće se tek kad se pregled zatvori, da poruka o rezultatu ne naleti na sheet.
    var confirmedForeignImport: ForeignWorkoutImport.Preview?
}

/// Postavke > Podaci: izvoz, uvoz i brisanje svih podataka (samo retci).
///
/// Prozori (izvoz, uvoz, pregled uvoza, potvrde i poruke) nisu na ovom `Section`: modifikator na sekciji
/// unutar `Form` primjenjuje se na svaki redak posebno, pa bi pet istih `fileImporter` i `sheet` modifikatora
/// istovremeno pokušalo prikazati isti prozor, koji se zato pojavi i odmah nestane. Prozori su u
/// `DataSettingsPresentations`, koji se stavlja jednom, na cijeli `Form`.
struct DataSettingsSection: View {
    let model: DataSettingsModel

    @Environment(\.modelContext) private var context

    var body: some View {
        Section {
            Button("Izvezi sve podatke (JSON)", systemImage: "square.and.arrow.up") { export(.json) }
            Button("Izvezi treninge (CSV)", systemImage: "tablecells") { export(.history) }
            Button("Izvezi mjerenja tijela (CSV)", systemImage: "tablecells") { export(.body) }
            Button("Uvezi iz datoteke", systemImage: "square.and.arrow.down") { model.showsImporter = true }
            Button(model.isDeleting ? "Brišem…" : "Obriši sve podatke", systemImage: "trash", role: .destructive) {
                model.showsDeleteStart = true
            }
            .disabled(model.isDeleting)
        } footer: {
            Text("""
                JSON je puna sigurnosna kopija. CSV datoteke možeš uvesti natrag u aplikaciju, a uvesti možeš i CSV \
                s treninzima iz druge aplikacije. Postojeći zapisi se pri uvozu ne mijenjaju.
                """)
        }
    }

    private func export(_ kind: DataSettingsModel.ExportKind) {
        DataSettingsActions(model: model, context: context, catalogStore: nil, onReset: {}).export(kind)
    }
}

extension View {
    /// Prozori za Postavke > Podaci. Stavlja se jednom, na `Form` koji sadrži `DataSettingsSection` (vidi `DataSettingsScreen`).
    func dataSettingsPresentations(_ model: DataSettingsModel, onReset: @escaping () -> Void) -> some View {
        modifier(DataSettingsPresentations(model: model, onReset: onReset))
    }
}

struct DataSettingsPresentations: ViewModifier {
    @Bindable var model: DataSettingsModel
    /// Poziva se nakon brisanja svih podataka, da ekran ponovno dohvati (zadane) postavke.
    let onReset: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore

    /// Briše li "Obriši sve podatke" i iCloud.
    private var deletesCloud: Bool { AppServices.isSyncRunning }

    private var actions: DataSettingsActions {
        DataSettingsActions(model: model, context: context, catalogStore: catalogStore, onReset: onReset)
    }

    func body(content: Content) -> some View {
        content
            .fileExporter(
                isPresented: $model.showsExporter, document: model.document, contentType: model.exportType,
                defaultFilename: model.exportName
            ) { result in
                if case .failure = result { actions.show("Izvoz nije uspio.", String(localized: "Datoteka nije spremljena.")) }
            }
            .fileImporter(isPresented: $model.showsImporter, allowedContentTypes: [.json, .commaSeparatedText]) { result in
                actions.importFile(result)
            }
            .sheet(item: $model.foreignImport, onDismiss: {
                if let preview = model.confirmedForeignImport {
                    model.confirmedForeignImport = nil
                    actions.importForeign(preview)
                }
            }, content: { request in
                ForeignImportSheet(preview: request.preview) { model.confirmedForeignImport = request.preview }
            })
            .confirmationDialog("Obriši sve podatke?", isPresented: $model.showsDeleteStart, titleVisibility: .visible) {
                Button("Prvo izvezi sigurnosnu kopiju") { actions.export(.json) }
                Button("Nastavi s brisanjem", role: .destructive) { model.showsDeleteConfirm = true }
            } message: {
                if deletesCloud {
                    Text("""
                        Briše sve treninge, predloške, rasporede, vlastite vježbe, mjerenja i postavke s ovog uređaja \
                        i iz tvog iClouda, pa time i s ostalih tvojih uređaja.
                        """)
                } else {
                    Text("Briše sve treninge, predloške, rasporede, vlastite vježbe, mjerenja i postavke s ovog uređaja.")
                }
            }
            .alert("Jesi li siguran?", isPresented: $model.showsDeleteConfirm) {
                Button("Obriši sve", role: .destructive) { actions.deleteAll() }
                Button("Odustani", role: .cancel) {}
            } message: {
                Text("Ovo se ne može poništiti.")
            }
            .alert(model.messageTitle, isPresented: $model.showsMessage) {
                Button("U redu", role: .cancel) {}
            } message: {
                Text(model.messageText)
            }
    }
}

/// Radnje za Postavke > Podaci nad zajedničkim stanjem.
@MainActor
private struct DataSettingsActions {
    let model: DataSettingsModel
    let context: ModelContext
    /// Potreban samo za uvoz iz druge aplikacije.
    let catalogStore: CatalogStore?
    let onReset: () -> Void

    func show(_ title: LocalizedStringKey, _ text: String) {
        model.messageTitle = title
        model.messageText = text
        model.showsMessage = true
    }

    func export(_ kind: DataSettingsModel.ExportKind) {
        do {
            let data: Data
            switch kind {
            case .json: data = try JSONBackup.export(from: context)
            case .history: data = Data(try CSVBackup.exportHistory(from: context).utf8)
            case .body: data = Data(try CSVBackup.exportBody(from: context).utf8)
            }
            model.document = BackupDocument(data: data)
            model.exportType = kind.contentType
            model.exportName = "\(kind.baseName)-\(Date.now.formatted(.iso8601.year().month().day()))"
            model.showsExporter = true
        } catch {
            show("Izvoz nije uspio.", String(localized: "Podaci se nisu mogli pripremiti."))
        }
    }

    func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task { await importFile(at: url) }
    }

    /// Čitanje i uvoz idu izvan glavne niti (uvoz u zasebnom kontekstu), da velika datoteka ne zamrzne
    /// aplikaciju. Spremljene promjene glavni kontekst preuzima sam.
    private func importFile(at url: URL) async {
        let container = context.container
        let isJSON = url.pathExtension.lowercased() == "json"
        do {
            let data = try await Task.detached(priority: .userInitiated) { try readImportFile(at: url) }.value
            let outcome: BackupImportResult
            if isJSON {
                outcome = try await Task.detached(priority: .userInitiated) {
                    try JSONBackup.importBackup(data, into: ModelContext(container))
                }.value
            } else {
                let text = String(decoding: data, as: UTF8.self)
                if ForeignWorkoutsCSV.matches(text) {
                    try previewForeign(text)
                    return
                }
                outcome = try await Task.detached(priority: .userInitiated) {
                    try CSVBackup.importAny(text, into: ModelContext(container))
                }.value
            }
            // Stara sigurnosna kopija može imati id-jeve vježbi iz starog kataloga.
            AppServices.migrateCatalogIds()
            show("Uvoz je gotov.", String(localized: "Dodano: \(outcome.added). Preskočeno (već postoje): \(outcome.skipped)."))
        } catch ImportFileError.tooLarge {
            show("Uvoz nije uspio.", String(localized: "Datoteka je prevelika. Najveća veličina je 50 MB."))
        } catch BackupError.newerVersion {
            show("Uvoz nije uspio.", String(localized: "Datoteka je iz novije verzije aplikacije."))
        } catch BackupError.invalidCSV(let line) {
            show("Uvoz nije uspio.", String(localized: "CSV nije ispravan (redak \(line)). Ništa nije uvezeno."))
        } catch {
            show("Uvoz nije uspio.", String(localized: "Ovo nije sigurnosna kopija ove aplikacije."))
        }
    }

    /// CSV s treninzima iz druge aplikacije: prvo pregled, uvoz tek nakon potvrde.
    private func previewForeign(_ text: String) throws {
        guard let catalogStore, let catalog = catalogStore.catalog else {
            show("Uvoz nije uspio.", String(localized: "Katalog se nije mogao učitati."))
            return
        }
        let preview = try ForeignWorkoutImport.preview(text, catalog: catalog, language: catalogStore.language, context: context)
        model.foreignImport = DataSettingsModel.ForeignImportRequest(preview: preview)
    }

    func importForeign(_ preview: ForeignWorkoutImport.Preview) {
        do {
            let outcome = try ForeignWorkoutImport.apply(preview, into: context)
            show("Uvoz je gotov.", String(localized: "Dodano: \(outcome.added). Preskočeno (već postoje): \(outcome.skipped)."))
        } catch {
            show("Uvoz nije uspio.", String(localized: "Treninzi se nisu mogli spremiti. Ništa nije uvezeno."))
        }
    }

    func deleteAll() {
        let scope = DataResetScope.resolve(isSyncRunning: AppServices.isSyncRunning, account: SyncMonitor.shared.account)
        switch scope {
        case .deviceOnly:
            deleteOnDevice()
        case .cloudUnavailable:
            show("Brisanje nije uspjelo.", String(localized: "iCloud trenutno nije dostupan, pa se podaci u njemu ne mogu obrisati. Ništa nije obrisano."))
        case .deviceAndCloud:
            model.isDeleting = true
            Task {
                do {
                    // Prvo iCloud: da se ne uspije, podaci obrisani samo na uređaju vratili bi se sinkronizacijom.
                    try await CloudDataReset.deleteCloudData()
                    deleteOnDevice()
                } catch {
                    show(
                        "Brisanje nije uspjelo.",
                        String(localized: "Podaci u iCloudu nisu obrisani. Provjeri internetsku vezu i pokušaj ponovno. Ništa nije obrisano.")
                    )
                }
                model.isDeleting = false
            }
        }
    }

    private func deleteOnDevice() {
        do {
            try DataReset.deleteAll(in: context)
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            DiagnosticsStore.shared.removeAll()
            onReset()
            show("Podaci su obrisani.", String(localized: "Aplikacija je vraćena na početno stanje."))
        } catch {
            show("Brisanje nije uspjelo.", String(localized: "Pokušaj ponovno."))
        }
    }
}

/// Najveća datoteka za uvoz. Sigurnosna kopija i višegodišnja povijest su daleko manje,
/// a puno veća datoteka mogla bi zbog memorije srušiti aplikaciju.
private enum DataSettingsActionsLimits {
    static let maximumImportBytes = 50 * 1024 * 1024
}

private enum ImportFileError: Error {
    case tooLarge
}

/// Čita odabranu datoteku (s pristupom izvan sandboxa) i odbija preveliku.
private func readImportFile(at url: URL) throws -> Data {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= DataSettingsActionsLimits.maximumImportBytes else { throw ImportFileError.tooLarge }
    return try Data(contentsOf: url)
}
