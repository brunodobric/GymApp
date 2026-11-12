import Catalog
import Foundation
import SwiftData
import Testing
import Units
@testable import Models

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

private let bench = ExerciseRef(catalogId: "bench-press", name: "Bench press")
private let squat = ExerciseRef(catalogId: "squat", name: "Squat")

/// Stvara završeni trening s jednom vježbom i zadanim serijama (težina, ponavljanja).
@discardableResult
private func makeSession(
    in context: ModelContext,
    exercise: ExerciseRef,
    startedAt: Date,
    state: SessionState = .finished,
    sets: [(Double, Int)] = [(80, 8)],
    removed: Bool = false
) -> Session {
    let session = Session(name: "Trening", startedAt: startedAt)
    session.state = state
    context.insert(session)
    let sessionExercise = SessionExercise(orderIndex: 0, exercise: exercise)
    sessionExercise.isRemoved = removed
    sessionExercise.session = session
    for (index, set) in sets.enumerated() {
        let log = SetLog(orderIndex: index)
        log.weightKg = set.0
        log.reps = set.1
        log.exercise = sessionExercise
    }
    return session
}

@Suite("Modeli")
struct ModelsTests {

    @Test("Predložak čuva redoslijed vježbi i serija preko orderIndex")
    func templateOrdering() throws {
        let context = try makeContext()
        let template = WorkoutTemplate(name: "Push")
        context.insert(template)
        for (index, ref) in [squat, bench].enumerated().reversed() {
            let exercise = TemplateExercise(orderIndex: index, exercise: ref)
            exercise.template = template
            for setIndex in (0..<3).reversed() {
                let set = TemplateSet(orderIndex: setIndex, targetWeightKg: 60 + Double(setIndex) * 5, targetReps: 8)
                set.exercise = exercise
            }
        }
        try context.save()

        let ordered = template.orderedExercises
        #expect(ordered.map(\.exerciseName) == ["Squat", "Bench press"])
        #expect(ordered[0].orderedSets.map(\.orderIndex) == [0, 1, 2])
        #expect(ordered[0].orderedSets.map(\.targetWeightKg) == [60, 65, 70])
    }

    @Test("Brisanje predloška ne briše odrađene treninge")
    func deletingTemplateKeepsSessions() throws {
        let context = try makeContext()
        let template = WorkoutTemplate(name: "Pull")
        context.insert(template)
        let templateExercise = TemplateExercise(orderIndex: 0, exercise: bench)
        templateExercise.template = template

        let session = makeSession(in: context, exercise: bench, startedAt: Date())
        session.templateId = template.id
        try context.save()

        context.delete(template)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TemplateExercise>()).isEmpty)
        let sessions = try context.fetch(FetchDescriptor<Session>())
        #expect(sessions.count == 1)
        #expect(sessions[0].orderedExercises.count == 1)
        #expect(sessions[0].orderedExercises[0].orderedSets.count == 1)
    }

    @Test("Brisanje rasporeda ne briše treninge ni predloške")
    func deletingScheduleKeepsTemplates() throws {
        let context = try makeContext()
        let template = WorkoutTemplate(name: "Legs")
        context.insert(template)
        let schedule = Schedule(name: "PPL")
        context.insert(schedule)
        let item = ScheduleItem(orderIndex: 0, kind: .workout, workoutTemplateId: template.id)
        item.schedule = schedule
        makeSession(in: context, exercise: squat, startedAt: Date())
        try context.save()

        context.delete(schedule)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ScheduleItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Session>()).count == 1)
    }

    @Test("Brisanje treninga briše njegove vježbe i serije")
    func deletingSessionCascades() throws {
        let context = try makeContext()
        let session = makeSession(in: context, exercise: bench, startedAt: Date(), sets: [(80, 8), (85, 6)])
        try context.save()

        context.delete(session)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<SessionExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)
    }

    @Test("Ključ vježbe razlikuje katalog i vlastite vježbe")
    func exerciseRefKey() {
        let id = UUID()
        #expect(bench.key == "c:bench-press")
        #expect(ExerciseRef(customExerciseId: id, name: "Moja").key == "u:\(id.uuidString)")
    }

    @Test("Zamjena vježbe u treningu ažurira ključ za upite")
    func exerciseKeyFollowsRef() {
        let exercise = SessionExercise(orderIndex: 0, exercise: bench)
        #expect(exercise.exerciseKey == "c:bench-press")
        exercise.exercise = squat
        #expect(exercise.exerciseKey == "c:squat")
        #expect(exercise.exerciseName == "Squat")
    }

    @Test("RPE prihvaća samo 1 do 10 u koracima od 0,5")
    func rpeValidation() {
        for valid in [1.0, 1.5, 7.5, 10.0] { #expect(RPE.isValid(valid)) }
        for invalid in [0.0, 0.5, 7.25, 10.5, 11.0, -1.0] { #expect(!RPE.isValid(invalid)) }
        #expect(RPE.rir(fromRPE: 8.5) == 1.5)
        #expect(RPE.rpe(fromRIR: 2) == 8)
    }

    @Test("Postavke imaju tvorničke vrijednosti i pretvaraju popis ploča")
    func settingsDefaults() throws {
        let context = try makeContext()
        let queries = GymQueries(context: context)
        let settings = try queries.settings()
        #expect(settings.weightUnit == .kilograms)
        #expect(settings.defaultRestSeconds == 90)
        #expect(settings.effortScale == .rpe)
        #expect(settings.availablePlatesKg == [1.25, 2.5, 5, 10, 15, 20, 25])

        settings.weightUnit = .pounds
        settings.availablePlatesKg = [2.5, 5]
        #expect(settings.availablePlatesRaw == "2.5,5.0")
        // Drugi poziv vraća isti zapis, ne stvara novi.
        #expect(try queries.settings().id == settings.id)
    }

    @Test("Live Activity prati temu i boju aplikacije dok se ne isključi")
    func liveActivityAppearance() throws {
        let context = try makeContext()
        let settings = try GymQueries(context: context).settings()
        #expect(settings.liveActivityFollowsApp)
        settings.theme = .light
        settings.accent = .purple
        #expect(settings.effectiveLiveActivityTheme == .light)
        #expect(settings.effectiveLiveActivityAccent == .purple)

        // Isključivanje kreće od aplikacijinih vrijednosti, pa se Live Activity ne mijenja.
        settings.setLiveActivityFollowsApp(false)
        #expect(settings.liveActivityTheme == .light)
        #expect(settings.liveActivityAccent == .purple)

        settings.liveActivityTheme = .dark
        settings.liveActivityAccent = .teal
        settings.theme = .system
        #expect(settings.effectiveLiveActivityTheme == .dark)
        #expect(settings.effectiveLiveActivityAccent == .teal)

        // Ponovno uključivanje vraća aplikacijine, a vlastite ostaju zapamćene.
        settings.setLiveActivityFollowsApp(true)
        #expect(settings.effectiveLiveActivityTheme == .system)
        #expect(settings.effectiveLiveActivityAccent == .purple)
        #expect(settings.liveActivityAccent == .teal)
    }

    @Test("Težina se u bazi čuva u kilogramima")
    func weightStoredInKilograms() throws {
        let context = try makeContext()
        let log = SetLog(orderIndex: 0)
        log.weightKg = WeightConversion.kilograms(from: 225, in: .pounds)
        context.insert(log)
        try context.save()
        let stored = try #require(try context.fetch(FetchDescriptor<SetLog>()).first?.weightKg)
        #expect(abs(stored - 102.0582) < 0.001)
    }

    @Test("Vrijednosti s nepoznatim tekstom vraćaju sigurnu zadanu")
    func unknownRawValues() {
        let set = SetLog(orderIndex: 0)
        set.kindRaw = "nepoznato"
        #expect(set.kind == .working)
        let session = Session(name: "x")
        session.stateRaw = "nepoznato"
        #expect(session.state == .finished)
    }
}

@Suite("Upiti")
struct QueriesTests {

    @Test("Aktivni trening je onaj u tijeku, najnoviji")
    func activeSession() throws {
        let context = try makeContext()
        let queries = GymQueries(context: context)
        #expect(try queries.activeSession() == nil)

        makeSession(in: context, exercise: bench, startedAt: Date(timeIntervalSince1970: 1000), state: .finished)
        makeSession(in: context, exercise: bench, startedAt: Date(timeIntervalSince1970: 2000), state: .active)
        let newest = makeSession(in: context, exercise: bench, startedAt: Date(timeIntervalSince1970: 3000), state: .active)
        makeSession(in: context, exercise: bench, startedAt: Date(timeIntervalSince1970: 4000), state: .discarded)
        try context.save()

        #expect(try queries.activeSession()?.id == newest.id)
    }

    @Test("Treninzi u rasponu: samo završeni, od najnovijeg")
    func sessionsInRange() throws {
        let context = try makeContext()
        let queries = GymQueries(context: context)
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let before = makeSession(in: context, exercise: bench, startedAt: base - day)
        let first = makeSession(in: context, exercise: bench, startedAt: base)
        let second = makeSession(in: context, exercise: bench, startedAt: base + day)
        makeSession(in: context, exercise: bench, startedAt: base + 2 * day, state: .active)
        makeSession(in: context, exercise: bench, startedAt: base + 3 * day, state: .discarded)
        let after = makeSession(in: context, exercise: bench, startedAt: base + 10 * day)
        try context.save()

        let result = try queries.finishedSessions(from: base, to: base + 5 * day)
        #expect(result.map(\.id) == [second.id, first.id])
        #expect(!result.contains { $0.id == before.id || $0.id == after.id })
    }

    @Test("Zadnje izvođenje vježbe preskače izbačene, nezavršene i druge vježbe")
    func lastPerformance() throws {
        let context = try makeContext()
        let queries = GymQueries(context: context)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        makeSession(in: context, exercise: bench, startedAt: base, sets: [(70, 8)])
        makeSession(in: context, exercise: bench, startedAt: base + 100, sets: [(80, 8), (85, 8)])
        makeSession(in: context, exercise: bench, startedAt: base + 200, sets: [(999, 1)], removed: true)
        makeSession(in: context, exercise: bench, startedAt: base + 300, state: .active, sets: [(999, 1)])
        makeSession(in: context, exercise: squat, startedAt: base + 400, sets: [(999, 1)])
        try context.save()

        let last = try #require(try queries.lastPerformance(of: bench))
        #expect(last.orderedSets.map(\.weightKg) == [80, 85])
        #expect(try queries.lastPerformance(of: ExerciseRef(catalogId: "nepoznato", name: "?")) == nil)
    }

    @Test("Duplikati po UUID-u se uklanjaju, a različiti zapisi ostaju")
    func deduplication() throws {
        let context = try makeContext()
        let shared = UUID()
        for _ in 0..<3 {
            let measurement = BodyMeasurement(kind: .weight, value: 80)
            measurement.id = shared
            context.insert(measurement)
        }
        context.insert(BodyMeasurement(kind: .weight, value: 81))
        try context.save()

        let removed = try Deduplication.removeDuplicates(of: BodyMeasurement.self, id: \.id, in: context)
        #expect(removed == 2)
        #expect(try context.fetch(FetchDescriptor<BodyMeasurement>()).count == 2)
        #expect(try Deduplication.removeAllDuplicates(in: context) == 0)
    }
}

@Suite("Vlastite vježbe")
struct CustomExerciseTests {

    @Test("Vlastita vježba bez povijesti se briše")
    func deletedWithoutHistory() throws {
        let context = try makeContext()
        let exercise = CustomExercise(name: "Moja vježba")
        context.insert(exercise)
        try context.save()

        #expect(try CustomExerciseStore.remove(exercise, in: context) == .deleted)
        #expect(try context.fetch(FetchDescriptor<CustomExercise>()).isEmpty)
    }

    @Test("Vlastita vježba s poviješću se arhivira, a povijest ostaje")
    func archivedWithHistory() throws {
        let context = try makeContext()
        let exercise = CustomExercise(name: "Moja vježba")
        context.insert(exercise)
        makeSession(in: context, exercise: exercise.ref, startedAt: Date())
        try context.save()

        #expect(try CustomExerciseStore.remove(exercise, in: context) == .archived)
        let stored = try context.fetch(FetchDescriptor<CustomExercise>())
        #expect(stored.count == 1)
        #expect(stored[0].isArchived)
        #expect(try context.fetch(FetchDescriptor<SessionExercise>()).count == 1)
    }

    @Test("Vlastita vježba u predlošku se također arhivira")
    func archivedWhenInTemplate() throws {
        let context = try makeContext()
        let exercise = CustomExercise(name: "Moja vježba")
        context.insert(exercise)
        let template = WorkoutTemplate(name: "Dan A")
        context.insert(template)
        let templateExercise = TemplateExercise(orderIndex: 0, exercise: exercise.ref)
        templateExercise.template = template
        try context.save()

        #expect(try CustomExerciseStore.remove(exercise, in: context) == .archived)
    }

    @Test("Svojstva vlastite vježbe i sažetak")
    func summaryAndAccessors() {
        let exercise = CustomExercise(name: "Povlačenje užeta", inputType: .duration)
        exercise.category = .back
        exercise.equipment = .other
        exercise.muscles = [.lats, .biceps]

        #expect(exercise.inputType == .duration)
        #expect(exercise.muscles == [.lats, .biceps])
        let summary = exercise.summary
        #expect(summary.isCustom)
        #expect(summary.category == .back)
        #expect(summary.ref.customExerciseId == exercise.id)
        #expect(summary.ref.key == "u:\(exercise.id.uuidString)")
    }

    @Test("Vrsta vlastite vježbe: odabrana ili, za stariju vježbu, po kategoriji")
    func customKind() {
        let exercise = CustomExercise(name: "Veslanje")
        #expect(exercise.kind == .strength)
        exercise.category = .cardio
        #expect(exercise.kind == .cardio && exercise.kindRaw.isEmpty)
        exercise.kind = .warmUp
        #expect(exercise.kindRaw == "warmUp")
        #expect(exercise.summary.kind == .warmUp)
        exercise.kindRaw = "nepoznato"
        #expect(exercise.kind == .cardio)
    }

    @Test("Referenca vodi na vježbu iz kataloga ili na vlastitu vježbu")
    func refSource() {
        let id = UUID()
        #expect(ExerciseRef(catalogId: "bench-press", name: "Bench").source == .catalog(id: "bench-press"))
        #expect(ExerciseRef(customExerciseId: id, name: "Moja").source == .custom(id: id))
        #expect(ExerciseRef(catalogId: nil, customExerciseId: nil, name: "Uvezena").source == nil)

        let exercise = CustomExercise(name: "Povlačenje užeta")
        #expect(exercise.summary.ref.source == exercise.summary.source)
    }
}

@Suite("Kartice na Početnoj")
struct DashboardLayoutTests {
    private func kinds(_ layout: DashboardLayout) throws -> [DashboardCardKind] {
        try layout.cards().compactMap(\.kind)
    }

    private func raw(_ layout: DashboardLayout) throws -> [String] {
        try layout.allCards().map(\.kindRaw)
    }

    @Test("Dodavanje ide na kraj i svaka vrsta samo jednom")
    func addsOncePerKind() throws {
        let layout = DashboardLayout(context: try makeContext())
        #expect(try layout.availableKinds() == DashboardCardKind.allCases)
        try layout.add(.bodyWeight)
        try layout.add(.plateCalculator)
        #expect(try layout.add(.bodyWeight) == nil)
        #expect(try kinds(layout) == [.bodyWeight, .plateCalculator])
        #expect(try layout.availableKinds() == [.thisWeek, .thisMonth, .thisYear, .lastWorkout])
    }

    @Test("Uklanjanje zatvara rupu u redoslijedu")
    func removeRenumbers() throws {
        let layout = DashboardLayout(context: try makeContext())
        for kind: DashboardCardKind in [.plateCalculator, .thisWeek, .bodyWeight] { try layout.add(kind) }
        try layout.remove(try layout.cards()[1])
        #expect(try layout.cards().map(\.orderIndex) == [0, 1])
        #expect(try kinds(layout) == [.plateCalculator, .bodyWeight])
        try layout.add(.thisWeek)
        #expect(try kinds(layout) == [.plateCalculator, .bodyWeight, .thisWeek])
    }

    @Test("Premještanje slijedi pravila onMove")
    func moves() throws {
        let layout = DashboardLayout(context: try makeContext())
        for kind: DashboardCardKind in [.plateCalculator, .thisWeek, .bodyWeight] { try layout.add(kind) }
        try layout.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(try kinds(layout) == [.thisWeek, .bodyWeight, .plateCalculator])
        try layout.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(try kinds(layout) == [.plateCalculator, .thisWeek, .bodyWeight])
        try layout.move(fromOffsets: IndexSet(integer: 0), toOffset: 1)
        #expect(try kinds(layout) == [.plateCalculator, .thisWeek, .bodyWeight])
    }

    @Test("Uklonjena zadana kartica se ne vraća kad Početna već ima kartice")
    func doesNotSeedOverExistingCards() throws {
        let layout = DashboardLayout(context: try makeContext())
        try layout.add(.bodyWeight)
        #expect(try layout.seedDefaults().isEmpty)
        #expect(try kinds(layout) == [.bodyWeight])
    }

    @Test("Prazna Početna dobiva Ovaj tjedan i Zadnji trening")
    func seedsDefaultsOnEmpty() throws {
        let layout = DashboardLayout(context: try makeContext())
        #expect(try layout.seedDefaults().count == 2)
        #expect(try kinds(layout) == [.thisWeek, .lastWorkout])
        #expect(try layout.seedDefaults().isEmpty)
        #expect(try layout.allCards().map(\.orderIndex) == [0, 1])
    }

    @Test("Prijelaz: tjedni volumen postaje Ovaj tjedan na istom mjestu, sljedeći trening nestaje")
    func upgradeReplacesRetiredKinds() throws {
        let context = try makeContext()
        context.insert(DashboardCard(kindRaw: "lastWorkout", orderIndex: 0))
        context.insert(DashboardCard(kindRaw: "nextWorkout", orderIndex: 1))
        context.insert(DashboardCard(kindRaw: "weeklyVolume", orderIndex: 2))
        context.insert(DashboardCard(kindRaw: "plateCalculator", orderIndex: 3))
        let layout = DashboardLayout(context: context)
        try layout.upgradeToWeekCard()
        #expect(try raw(layout) == ["lastWorkout", "thisWeek", "plateCalculator"])
        #expect(try layout.allCards().map(\.orderIndex) == [0, 1, 2])
    }

    @Test("Prijelaz bez tjednog volumena dodaje Ovaj tjedan na vrh")
    func upgradeAddsWeekOnTop() throws {
        let context = try makeContext()
        context.insert(DashboardCard(kindRaw: "lastWorkout", orderIndex: 0))
        context.insert(DashboardCard(kindRaw: "nextWorkout", orderIndex: 1))
        let layout = DashboardLayout(context: context)
        try layout.upgradeToWeekCard()
        #expect(try raw(layout) == ["thisWeek", "lastWorkout"])
        // Drugi prolaz ništa ne mijenja.
        try layout.upgradeToWeekCard()
        #expect(try raw(layout) == ["thisWeek", "lastWorkout"])
    }

    @Test("Prijelaz ne dira Početnu koja već ima Ovaj tjedan ni praznu Početnu")
    func upgradeKeepsExistingWeek() throws {
        let empty = DashboardLayout(context: try makeContext())
        try empty.upgradeToWeekCard()
        #expect(try empty.allCards().isEmpty)

        let context = try makeContext()
        context.insert(DashboardCard(kindRaw: "bodyWeight", orderIndex: 0))
        context.insert(DashboardCard(kindRaw: "thisWeek", orderIndex: 1))
        context.insert(DashboardCard(kindRaw: "weeklyVolume", orderIndex: 2))
        let layout = DashboardLayout(context: context)
        try layout.upgradeToWeekCard()
        #expect(try raw(layout) == ["bodyWeight", "thisWeek"])
    }

    @Test("Dvije uzastopne male kartice dijele red")
    func rows() {
        #expect(DashboardLayout.rows([.thisWeek, .bodyWeight, .plateCalculator, .lastWorkout])
            == [[.thisWeek], [.bodyWeight, .plateCalculator], [.lastWorkout]])
        #expect(DashboardLayout.rows([.bodyWeight, .lastWorkout, .plateCalculator])
            == [[.bodyWeight], [.lastWorkout], [.plateCalculator]])
        #expect(DashboardLayout.rows([]).isEmpty)
    }

    @Test("Nepoznata vrsta se ne prikazuje, ali ostaje u bazi")
    func unknownKindIsKept() throws {
        let context = try makeContext()
        context.insert(DashboardCard(kindRaw: "buducaVrsta", orderIndex: 0))
        let layout = DashboardLayout(context: context)
        try layout.add(.thisWeek)
        try layout.move(fromOffsets: IndexSet(integer: 0), toOffset: 1)
        #expect(try kinds(layout) == [.thisWeek])
        #expect(try layout.allCards().count == 2)
    }
}

@Suite("Onboarding")
struct OnboardingTests {
    @Test("Odgovori ulaze u postavke i mjerenja")
    func appliesAnswers() throws {
        let context = try makeContext()
        var answers = OnboardingAnswers()
        answers.goal = .strength
        answers.unit = .pounds
        answers.weight = 200
        answers.heightCm = 180
        answers.wantsHealthKit = true
        answers.experience = .intermediate
        answers.equipment = [.barbell, .dumbbell]
        answers.daysPerWeek = 4
        answers.sex = .female
        try OnboardingApplier(context: context).apply(answers)

        let settings = try GymQueries(context: context).settings()
        #expect(settings.goal == .strength && settings.weightUnit == .pounds)
        #expect(settings.sex == .female && settings.bodyMapFemale)
        #expect(settings.experience == .intermediate && settings.equipment == [.barbell, .dumbbell])
        #expect(settings.trainingDaysPerWeek == 4 && settings.wantsHealthKit && settings.onboardingCompleted)

        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let weight = try #require(measurements.first { $0.kindRaw == "weight" })
        #expect(abs(weight.value - 90.718474) < 0.0001) // 200 lbs spremljeno u kg
        #expect(measurements.first { $0.kindRaw == "height" }?.value == 180)
    }

    @Test("Prazni i nerazumni odgovori se ne spremaju")
    func ignoresInvalid() throws {
        let context = try makeContext()
        var answers = OnboardingAnswers()
        answers.weight = 5
        answers.heightCm = 20
        answers.daysPerWeek = 9
        try OnboardingApplier(context: context).apply(answers)

        let settings = try GymQueries(context: context).settings()
        #expect(settings.goal == nil && settings.experience == nil && settings.equipment.isEmpty)
        #expect(settings.sex == nil && !settings.bodyMapFemale)
        #expect(settings.trainingDaysPerWeek == nil && settings.onboardingCompleted)
        #expect(try context.fetch(FetchDescriptor<BodyMeasurement>()).isEmpty)
    }

    @Test("Preskakanje samo označava da je onboarding obavljen")
    func skipOnlyMarksDone() throws {
        let context = try makeContext()
        try OnboardingApplier(context: context).skip()
        let settings = try GymQueries(context: context).settings()
        #expect(settings.onboardingCompleted && settings.goal == nil && settings.weightUnit == .kilograms)
        #expect(!settings.wantsHealthKit)
    }

    @Test("Odgovor o Apple Zdravlju sprema se i nakon preskakanja")
    func skipKeepsHealthAnswer() throws {
        let context = try makeContext()
        try OnboardingApplier(context: context).skip(wantsHealthKit: true)
        let settings = try GymQueries(context: context).settings()
        #expect(settings.onboardingCompleted && settings.wantsHealthKit && settings.goal == nil)
    }

    @Test("Naknadno ispunjavanje kreće od spremljenih odgovora, bez težine i visine")
    func answersFromSettings() throws {
        let context = try makeContext()
        let settings = try GymQueries(context: context).settings()
        settings.goal = .hypertrophy
        settings.trainingDaysPerWeek = 3
        settings.weightUnit = .pounds
        settings.sex = .male
        settings.wantsHealthKit = true
        settings.equipment = EquipmentPreset.dumbbells.equipment
        let answers = OnboardingAnswers(settings: settings)
        #expect(answers.goal == .hypertrophy && answers.daysPerWeek == 3 && answers.unit == .pounds)
        #expect(answers.sex == .male && answers.wantsHealthKit && answers.experience == nil)
        #expect(EquipmentPreset.matching(answers.equipment) == .dumbbells)
        #expect(answers.weight == nil && answers.heightCm == nil)

        // Ponovno spremanje istih odgovora ne dodaje mjerenja.
        try OnboardingApplier(context: context).apply(answers)
        #expect(try context.fetch(FetchDescriptor<BodyMeasurement>()).isEmpty)
    }
}

@Suite("Premještanje elemenata")
struct OrderingTests {

    @Test("Isto kao onMove u SwiftUI-ju: naprijed, natrag i više elemenata")
    func moves() {
        var forward = ["a", "b", "c", "d"]
        forward.moveElements(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(forward == ["b", "c", "a", "d"])

        var backward = ["a", "b", "c", "d"]
        backward.moveElements(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(backward == ["d", "a", "b", "c"])

        var several = ["a", "b", "c", "d", "e"]
        several.moveElements(fromOffsets: IndexSet([0, 2]), toOffset: 5)
        #expect(several == ["b", "d", "e", "a", "c"])
    }

    @Test("Nepostojeći indeks se preskače, a odredište se ograničava")
    func invalidOffsets() {
        var list = [1, 2, 3]
        list.moveElements(fromOffsets: IndexSet([7]), toOffset: 0)
        #expect(list == [1, 2, 3])
        list.moveElements(fromOffsets: IndexSet(integer: 0), toOffset: 99)
        #expect(list == [2, 3, 1])
    }
}
