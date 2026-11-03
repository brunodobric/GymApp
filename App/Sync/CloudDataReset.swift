import CloudKit

/// Brisanje podataka aplikacije iz korisnikovog iClouda ("Obriši sve podatke").
///
/// SwiftData (preko `NSPersistentCloudKitContainer`) sprema sve zapise u jednu zonu privatne baze.
/// Brisanje zone briše sve zapise odjednom, i one koji još nisu stigli na ovaj uređaj. Ostali uređaji
/// pri sljedećoj sinkronizaciji vide da zone više nema i brišu svoje lokalne kopije.
@MainActor
enum CloudDataReset {
    static let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

    static func deleteCloudData() async throws {
        let database = CKContainer(identifier: AppServices.cloudContainerIdentifier).privateCloudDatabase
        do {
            _ = try await database.deleteRecordZone(withID: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // Zone nema, pa u iCloudu nema ni podataka.
        }
    }
}
