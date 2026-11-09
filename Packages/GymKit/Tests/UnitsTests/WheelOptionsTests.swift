import Testing
@testable import Units

@Suite("Kotačić za unos serije")
struct WheelOptionsTests {

    @Test("Kilogrami idu od 0 do 500 u koracima od 2,5")
    func kilogramSteps() {
        let values = WheelOptions.weights(for: .kilograms)
        #expect(values.first == 0)
        #expect(values[1] == 2.5)
        #expect(values.last == 500)
        #expect(values.count == 201)
    }

    @Test("Funte idu od 0 do 1100 u koracima od 5")
    func poundSteps() {
        let values = WheelOptions.weights(for: .pounds)
        #expect(values[1] == 5)
        #expect(values.last == 1100)
        #expect(values.count == 221)
    }

    @Test("Korak vježbe mijenja razmak, a najveća težina ostaje")
    func customStep() {
        let dumbbells = WheelOptions.weights(for: .kilograms, step: 2)
        #expect(Array(dumbbells.prefix(4)) == [0, 2, 4, 6])
        #expect(dumbbells.last == 500)
        #expect(dumbbells.count == 251)

        let micro = WheelOptions.weights(for: .kilograms, step: 1.25)
        #expect(micro[1] == 1.25)
        #expect(micro.contains(81.25))
        #expect(micro.last == 500)

        // Korak koji ne dijeli najveću težinu staje ispod nje.
        #expect(WheelOptions.weights(for: .pounds, step: 15).last == 1095)
        // Nevaljan korak vraća korak jedinice.
        #expect(WheelOptions.weights(for: .kilograms, step: 0)[1] == 2.5)
        #expect(WheelOptions.weights(for: .kilograms, step: 2, including: 13).contains(13))
    }

    @Test("Težina izvan koraka dodaje se na svoje mjesto")
    func offStepWeight() {
        let values = WheelOptions.weights(for: .kilograms, including: 83)
        #expect(values.count == 202)
        let index = values.firstIndex(of: 83)
        #expect(index != nil)
        #expect(values[index! - 1] == 82.5)
        #expect(values[index! + 1] == 85)
    }

    @Test("Težina na koraku se ne dodaje dvaput")
    func onStepWeight() {
        #expect(WheelOptions.weights(for: .kilograms, including: 82.5).count == 201)
        #expect(WheelOptions.weights(for: .kilograms, including: 82.5004).count == 201)
    }

    @Test("Težina veća od najveće dodaje se na kraj")
    func weightAboveMaximum() {
        #expect(WheelOptions.weights(for: .kilograms, including: 520).last == 520)
    }

    @Test("Ponavljanja idu od 1 do 50")
    func repsRange() {
        let values = WheelOptions.reps()
        #expect(values.first == 1)
        #expect(values.last == 50)
        #expect(values.count == 50)
    }

    @Test("Ponavljanja izvan raspona dodaju se na svoje mjesto")
    func repsOutsideRange() {
        #expect(WheelOptions.reps(including: 60).last == 60)
        #expect(WheelOptions.reps(including: 0).first == 0)
        #expect(WheelOptions.reps(including: 8).count == 50)
    }

    @Test("Kotačić se postavlja na najbližu vrijednost")
    func nearestValue() {
        let values = WheelOptions.weights(for: .kilograms)
        #expect(WheelOptions.nearest(to: 81, in: values) == 80)
        #expect(WheelOptions.nearest(to: 81.6, in: values) == 82.5)
        #expect(WheelOptions.nearest(to: 900, in: values) == 500)
        #expect(WheelOptions.nearest(to: 1, in: []) == nil)
    }

    @Test("Početne vrijednosti")
    func defaults() {
        #expect(WheelOptions.defaultWeight(for: .kilograms, isExtraLoad: false) == 20)
        #expect(WheelOptions.defaultWeight(for: .pounds, isExtraLoad: false) == 45)
        #expect(WheelOptions.defaultWeight(for: .kilograms, isExtraLoad: true) == 0)
        #expect(WheelOptions.defaultReps == 10)
    }
}
