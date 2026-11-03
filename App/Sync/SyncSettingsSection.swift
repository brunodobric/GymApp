import Models
import SwiftUI

/// Postavke > iCloud: uključivanje sinkronizacije i njezino stanje.
struct SyncSettingsSection: View {
    @Bindable private var monitor = SyncMonitor.shared

    var body: some View {
        let status = monitor.status
        Section {
            if AppServices.isCloudSyncSupported {
                Toggle("Sinkronizacija preko iClouda", isOn: $monitor.isEnabled)
            }
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title)
                    if let detail = status.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status.needsAttention ? Color.orange : Color.secondary)
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("iCloud")
        } footer: {
            Text(status.footer)
        }
        // Račun se mogao promijeniti dok je aplikacija bila u pozadini.
        .task { monitor.refreshAccount() }
    }
}

extension SyncStatus {
    var title: LocalizedStringKey {
        switch self {
        case .unavailable: "Sinkronizacija nije dostupna"
        case .off: "Sinkronizacija isključena"
        case .willTurnOn: "Uključuje se nakon ponovnog pokretanja"
        case .willTurnOff: "Isključuje se nakon ponovnog pokretanja"
        case .startFailed: "Sinkronizacija nije pokrenuta"
        case .checkingAccount: "Provjeravam iCloud…"
        case .noAccount: "iCloud nije prijavljen"
        case .restricted: "iCloud je ograničen"
        case .accountUnavailable: "iCloud trenutno nije dostupan"
        case .syncing: "Sinkroniziram…"
        case .synced: "Sinkronizirano preko iClouda"
        case .failed(.quotaExceeded): "iCloud je pun"
        case .failed(.network): "Čeka internetsku vezu"
        case .failed(.notAuthenticated): "iCloud traži ponovnu prijavu"
        case .failed(.other): "Sinkronizacija nije uspjela"
        }
    }

    var detail: String? {
        switch self {
        case .synced(let lastSync?):
            String(localized: "Zadnja sinkronizacija: \(lastSync.formatted(.relative(presentation: .named)))")
        case .noAccount:
            String(localized: "Prijavi se u aplikaciji Postavke (tvoje ime na vrhu).")
        case .restricted:
            String(localized: "Ograničenja na uređaju ne dopuštaju iCloud.")
        case .startFailed:
            String(localized: "Pokušaj zatvoriti i ponovno otvoriti aplikaciju.")
        case .failed(.quotaExceeded):
            String(localized: "Oslobodi prostor u iCloudu da se promjene nastave slati.")
        case .failed(.notAuthenticated):
            String(localized: "Prijavi se ponovno u aplikaciji Postavke.")
        default:
            nil
        }
    }

    var systemImage: String {
        switch self {
        case .unavailable, .off, .noAccount, .restricted: "icloud.slash"
        case .willTurnOn, .willTurnOff, .syncing, .checkingAccount: "arrow.triangle.2.circlepath.icloud"
        case .startFailed, .accountUnavailable, .failed: "exclamationmark.icloud"
        case .synced: "checkmark.icloud"
        }
    }

    var footer: LocalizedStringKey {
        switch self {
        case .unavailable:
            "Ova verzija aplikacije potpisana je bez iCloud dozvole, pa se podaci spremaju samo na ovom uređaju."
        case .willTurnOn, .willTurnOff:
            "Promjena vrijedi kad zatvoriš aplikaciju (povuci je prema gore u prikazu otvorenih aplikacija) i ponovno je otvoriš."
        case .off, .startFailed, .noAccount, .restricted:
            "Podaci se spremaju samo na ovom uređaju. Katalog vježbi je dio aplikacije i ne sinkronizira se."
        default:
            """
            Treninzi, predlošci, rasporedi, vlastite vježbe, mjerenja i postavke sinkroniziraju se preko tvog iClouda \
            između tvojih uređaja. Katalog vježbi je dio aplikacije i ne sinkronizira se.
            """
        }
    }
}
