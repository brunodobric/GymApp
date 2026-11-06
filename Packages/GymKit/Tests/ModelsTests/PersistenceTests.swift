import Foundation
import Testing
@testable import Models

@Suite("Baza koja se ne može otvoriti")
struct StoreRecoveryTests {

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "GymKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Datoteke obje baze premještaju se u novu mapu, a ništa se ne briše")
    func movesAllFiles() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let user = directory.appending(path: "User.store")
        let health = directory.appending(path: "HealthLocal.store")
        let files = ["User.store", "User.store-shm", "User.store-wal", "HealthLocal.store"]
        for name in files {
            try Data(name.utf8).write(to: directory.appending(path: name))
        }
        try FileManager.default.createDirectory(at: directory.appending(path: ".User_SUPPORT"), withIntermediateDirectories: true)
        try Data("drugo".utf8).write(to: directory.appending(path: "Drugo.txt"))

        let destination = try GymPersistence.moveStoresAside([user, health], now: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(destination.lastPathComponent == "Neotvorena baza 1800000000")
        for name in files + [".User_SUPPORT"] {
            #expect(!FileManager.default.fileExists(atPath: directory.appending(path: name).path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: destination.appending(path: name).path(percentEncoded: false)))
        }
        #expect(try Data(contentsOf: destination.appending(path: "User.store-wal")) == Data("User.store-wal".utf8))
        // Ostale datoteke u mapi se ne diraju.
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "Drugo.txt").path(percentEncoded: false)))
    }

    @Test("Baza koja ne postoji ne smeta")
    func missingFiles() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = try GymPersistence.moveStoresAside([directory.appending(path: "User.store")])
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path(percentEncoded: false)).isEmpty)
    }
}
