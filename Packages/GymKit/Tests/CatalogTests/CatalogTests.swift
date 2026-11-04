import Foundation
import Testing
@testable import Catalog

private func exercise(
    _ id: String,
    hr: String?,
    en: String,
    category: ExerciseCategory = .chest,
    muscles: [Muscle] = [.chest],
    equipment: Equipment = .barbell
) -> ExerciseSummary {
    ExerciseSummary(
        source: .catalog(id: id),
        name: hr ?? en,
        alternativeNames: [en],
        category: category,
        muscles: muscles,
        equipment: equipment,
        isArchived: false
    )
}

private let sample = [
    exercise("squat", hr: "Čučanj sa šipkom", en: "Barbell Squat", category: .legs, muscles: [.quadriceps]),
    exercise("bench", hr: "Potisak šipkom s klupe", en: "Barbell Bench Press"),
    exercise("curl", hr: "Pregib bučicama", en: "Dumbbell Curl", category: .arms, muscles: [.biceps], equipment: .dumbbell),
    exercise("row", hr: "Veslanje šipkom", en: "Barbell Row", category: .back, muscles: [.lats]),
    exercise("dead", hr: "Mrtvo dizanje", en: "Deadlift", category: .back, muscles: [.lowerBack]),
]

@Suite("Pretraga kataloga")
struct SearchTests {

    @Test("Pretraga ne razlikuje velika slova ni dijakritike")
    func diacritics() {
        var filter = ExerciseFilter()
        filter.query = "cucanj"
        #expect(ExerciseSearch.apply(filter, to: sample).map(\.id) == ["c:squat"])
        filter.query = "ČUČANJ"
        #expect(ExerciseSearch.apply(filter, to: sample).map(\.id) == ["c:squat"])
    }

    @Test("Đ se pretražuje kao d")
    func crossedD() {
        #expect(ExerciseSearch.normalize("Đurđica") == "durdica")
    }

    @Test("Pronalazi i po engleskom nazivu")
    func englishName() {
        var filter = ExerciseFilter()
        filter.query = "bench"
        #expect(ExerciseSearch.apply(filter, to: sample).map(\.id) == ["c:bench"])
    }

    @Test("Sve riječi upita moraju postojati, bilo kojim redoslijedom")
    func allTokens() {
        var filter = ExerciseFilter()
        filter.query = "šipkom potisak"
        #expect(ExerciseSearch.apply(filter, to: sample).map(\.id) == ["c:bench"])
        filter.query = "šipkom xyz"
        #expect(ExerciseSearch.apply(filter, to: sample).isEmpty)
    }

    @Test("Pronalazi po opremi, mišiću i kategoriji, a vježbe s upitom u nazivu idu prve")
    func labels() {
        let labels = ExerciseSearchLabels(
            category: { $0 == .back ? "Leđa" : "Kategorija" },
            muscle: { $0 == .biceps ? "Biceps" : "Mišić" },
            equipment: { $0 == .dumbbell ? "Bučice" : "Šipka" }
        )
        var filter = ExerciseFilter()
        filter.query = "bucice"
        #expect(ExerciseSearch.apply(filter, to: sample, labels: labels).map(\.id) == ["c:curl"])
        filter.query = "biceps"
        #expect(ExerciseSearch.apply(filter, to: sample, labels: labels).map(\.id) == ["c:curl"])
        filter.query = "leđa šipka"
        #expect(ExerciseSearch.apply(filter, to: sample, labels: labels).map(\.id) == ["c:dead", "c:row"])
        // "Šipka" je oprema svih osim pregiba, ali vježbe sa "šipkom" u nazivu idu ispred mrtvog dizanja.
        filter.query = "sipk"
        #expect(ExerciseSearch.apply(filter, to: sample, labels: labels).map(\.id).last == "c:dead")
        // Bez naziva pretraga ostaje samo po nazivu vježbe.
        filter.query = "bucice"
        #expect(ExerciseSearch.apply(filter, to: sample).isEmpty)
    }

    @Test("Nazivi koji počinju upitom idu prvi")
    func relevanceOrder() {
        var filter = ExerciseFilter()
        filter.query = "sip"
        // "Veslanje šipkom" i ostali sadrže riječ koja počinje upitom, nijedan ne počinje njime.
        let ids = ExerciseSearch.apply(filter, to: sample).map(\.id)
        #expect(Set(ids) == ["c:squat", "c:bench", "c:row"])

        filter.query = "mrtvo"
        #expect(ExerciseSearch.apply(filter, to: sample).map(\.id) == ["c:dead"])
    }

    @Test("Bez upita rezultat je abecedni")
    func alphabetical() {
        let names = ExerciseSearch.apply(ExerciseFilter(), to: sample).map(\.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(names.count == sample.count)
    }

    @Test("Filteri se kombiniraju")
    func filters() {
        var filter = ExerciseFilter()
        filter.categories = [.back]
        #expect(Set(ExerciseSearch.apply(filter, to: sample).map(\.id)) == ["c:row", "c:dead"])
        filter.muscles = [.lats]
        #expect(ExerciseSearch.apply(filter, to: sample).map(\.id) == ["c:row"])
        filter = ExerciseFilter()
        filter.equipment = [.dumbbell]
        #expect(ExerciseSearch.apply(filter, to: sample).map(\.id) == ["c:curl"])
        #expect(filter.isActive)
    }

    @Test("Vlastite i službene vježbe te arhiva")
    func originAndArchive() {
        let custom = ExerciseSummary(
            source: .custom(id: UUID()), name: "Moja vježba", category: .core, muscles: [.abdominals],
            equipment: .bodyweight, isArchived: false
        )
        let archived = ExerciseSummary(
            source: .custom(id: UUID()), name: "Stara vježba", category: .core, muscles: [.abdominals],
            equipment: .bodyweight, isArchived: true
        )
        let all = sample + [custom, archived]

        var filter = ExerciseFilter()
        #expect(!ExerciseSearch.apply(filter, to: all).contains { $0.id == archived.id })
        filter.includeArchived = true
        #expect(ExerciseSearch.apply(filter, to: all).contains { $0.id == archived.id })

        filter = ExerciseFilter()
        filter.origin = .custom
        #expect(ExerciseSearch.apply(filter, to: all).map(\.id) == [custom.id])
        filter.origin = .official
        #expect(ExerciseSearch.apply(filter, to: all).count == sample.count)
    }
}

@Suite("Katalog")
struct CatalogDataTests {

    /// Stvarni katalog iz repozitorija (Resources/Catalog), da se pokvaren build uhvati u CI-ju.
    private static func loadBundledCatalog() throws -> (ExerciseCatalog, URL) {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Catalog")
        let data = try Data(contentsOf: directory.appendingPathComponent("catalog.json"))
        return (try ExerciseCatalog(data: data), directory)
    }

    @Test("catalog.json se učitava i ima 150 do 200 vježbi")
    func loads() throws {
        let (catalog, _) = try Self.loadBundledCatalog()
        #expect((150...200).contains(catalog.exercises.count))
        #expect(catalog.source.license == "Unlicense")
    }

    @Test("Id-evi su jedinstveni, svaka vježba ima hrvatski naziv, upute i slike na disku")
    func integrity() throws {
        let (catalog, directory) = try Self.loadBundledCatalog()
        #expect(Set(catalog.exercises.map(\.id)).count == catalog.exercises.count)
        for exercise in catalog.exercises {
            #expect(exercise.name["en"] != nil, "\(exercise.id): nema engleskog naziva")
            #expect(exercise.name["hr"] != nil, "\(exercise.id): nema hrvatskog naziva")
            #expect(!exercise.displayInstructions(language: "en").isEmpty, "\(exercise.id): nema uputa")
            #expect(!exercise.primaryMuscles.isEmpty, "\(exercise.id): nema primarnog mišića")
            #expect(!exercise.images.isEmpty, "\(exercise.id): nema slika")
            for image in exercise.images {
                let exists = FileManager.default.fileExists(atPath: directory.appendingPathComponent(image).path)
                #expect(exists, "\(exercise.id): nema datoteke \(image)")
            }
        }
    }

    @Test("Mapirane vježbe imaju oba crteža u asset catalogu, a ostale zadržavaju fotografije")
    func drawingsOnDisk() throws {
        let (catalog, directory) = try Self.loadBundledCatalog()
        let assets = directory.deletingLastPathComponent().appendingPathComponent("Drawings/Drawings.xcassets")
        #expect(catalog.drawingsSource?.name == "Everkinetic")
        #expect(catalog.drawingsSource?.license == "CC BY-SA 4.0")
        let drawn = catalog.exercises.filter { $0.drawings != nil }
        #expect(drawn.count >= 80, "premalo vježbi s crtežima: \(drawn.count)")
        for exercise in drawn {
            guard case let .drawing(start, end) = exercise.illustration else {
                Issue.record("\(exercise.id): crtež nema oba položaja")
                continue
            }
            for name in [start, end] {
                let svg = assets.appendingPathComponent("\(name).imageset/\(name).svg")
                #expect(FileManager.default.fileExists(atPath: svg.path), "\(exercise.id): nema crteža \(name)")
            }
        }
        // Vježbe bez crteža i dalje imaju fotografije.
        for exercise in catalog.exercises where exercise.drawings == nil {
            #expect(exercise.illustration == .photos(exercise.images), "\(exercise.id): nema ni crteža ni slika")
        }
        let squat = try #require(catalog.exercise(withID: "Barbell_Squat"))
        #expect(squat.illustration == .drawing(start: "Everkinetic-0122-start", end: "Everkinetic-0122-end"))
    }

    @Test("Prikaz vraća engleski kad prijevoda nema")
    func languageFallback() throws {
        let (catalog, _) = try Self.loadBundledCatalog()
        let exercise = try #require(catalog.exercise(withID: "Pushups"))
        #expect(exercise.displayName(language: "en") == "Pushups")
        #expect(exercise.displayName(language: "hr") == "Sklekovi")
        #expect(exercise.displayName(language: "de") == "Pushups")
        #expect(exercise.inputType == .bodyweight)
        #expect(catalog.exercise(withID: "ne-postoji") == nil)
    }

    @Test("Pretraga na stvarnom katalogu je brza i pronalazi očekivane vježbe")
    func realSearch() throws {
        let (catalog, _) = try Self.loadBundledCatalog()
        let summaries = catalog.summaries(language: "hr")
        var filter = ExerciseFilter()
        filter.query = "cucanj"
        let result = ExerciseSearch.apply(filter, to: summaries)
        #expect(result.contains { $0.id == "c:Barbell_Squat" })
        filter.query = "bench press"
        #expect(ExerciseSearch.apply(filter, to: summaries).contains { $0.id == "c:Barbell_Bench_Press_-_Medium_Grip" })
    }
}
