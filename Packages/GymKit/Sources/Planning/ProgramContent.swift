import Catalog
import Models

// Sadržaj gotovih programa: izvedbe vježbi po opremi, obrasci kretanja i treninzi.
// Volumen (tjedne serije po mišiću) i učestalost provjeravaju testovi u `ProgramTests`.

extension ProgramLibrary {

    // MARK: Izvedbe

    static func option(_ id: String, _ input: ExerciseInputType, _ equipment: Set<Equipment>) -> ExerciseOption {
        ExerciseOption(catalogId: id, inputType: input, equipment: equipment)
    }

    static func barbell(_ id: String) -> ExerciseOption { option(id, .weightReps, [.barbell]) }
    static func dumbbell(_ id: String) -> ExerciseOption { option(id, .weightReps, [.dumbbell]) }
    static func cable(_ id: String) -> ExerciseOption { option(id, .weightReps, [.cable]) }
    static func machine(_ id: String) -> ExerciseOption { option(id, .weightReps, [.machine]) }
    static func band(_ id: String) -> ExerciseOption { option(id, .weightReps, [.bands]) }
    static func bodyweight(_ id: String) -> ExerciseOption { option(id, .bodyweight, []) }
    /// Zgibovi i slično: treba šipka.
    static func bar(_ id: String) -> ExerciseOption { option(id, .bodyweight, [.other]) }

    // MARK: Obrasci kretanja

    static let squat = [barbell("barbell-squat"), dumbbell("dumbbell-goblet-squat"), bodyweight("bodyweight-squat")]
    static let legPress = [
        machine("machine-leg-press"), dumbbell("dumbbell-bulgarian-split-squat"), bodyweight("bulgarian-split-squat"),
    ]
    static let splitSquat = [dumbbell("dumbbell-bulgarian-split-squat"), bodyweight("bulgarian-split-squat")]
    static let deadlift = [
        barbell("barbell-deadlift"), dumbbell("dumbbell-deadlift"), bodyweight("single-leg-hip-thrust"),
    ]
    static let romanianDeadlift = [
        barbell("barbell-romanian-deadlift"), dumbbell("dumbbell-stiff-leg-deadlift"), band("band-romanian-deadlift"),
        bodyweight("single-leg-hip-thrust"),
    ]
    static let hipThrust = [
        barbell("barbell-hip-thrust"), dumbbell("dumbbell-heels-elevated-hip-thrust"), bodyweight("glute-bridge"),
    ]
    static let legCurl = [
        machine("lying-leg-curl"), dumbbell("dumbbell-leg-curl"), band("band-leg-curl"), bodyweight("towel-slide-leg-curl"),
    ]
    static let legExtension = [machine("machine-leg-extension")]
    static let calfRaise = [
        machine("standing-calf-raise-machine"), dumbbell("dumbbell-single-leg-calf-raise"),
        bodyweight("single-leg-standing-calf-raise"),
    ]

    static let benchPress = [barbell("barbell-bench-press"), dumbbell("dumbbell-bench-press"), bodyweight("push-up")]
    static let dumbbellPress = [dumbbell("dumbbell-bench-press"), machine("machine-chest-press"), bodyweight("push-up")]
    static let inclinePress = [dumbbell("dumbbell-incline-bench-press"), bodyweight("push-up")]
    static let overheadPress = [
        barbell("barbell-overhead-press"), dumbbell("dumbbell-seated-overhead-press"), band("band-overhead-press"),
        bodyweight("pike-push-up"),
    ]
    static let dumbbellOverheadPress = [
        dumbbell("dumbbell-seated-overhead-press"), band("band-overhead-press"), bodyweight("pike-push-up"),
    ]
    static let chestFly = [cable("cable-pec-fly"), dumbbell("dumbbell-chest-fly")]
    static let lateralRaise = [dumbbell("dumbbell-lateral-raise"), band("band-lateral-raise")]
    static let facePull = [cable("machine-face-pulls"), band("band-high-face-pull"), dumbbell("dumbbell-rear-delt-fly")]
    static let tricepsPushdown = [
        cable("cable-bar-pushdown"), dumbbell("dumbbell-seated-overhead-tricep-extension"), bodyweight("bench-dips"),
    ]
    static let tricepsExtension = [
        dumbbell("dumbbell-skullcrusher"), cable("cable-bar-pushdown"), bodyweight("diamond-push-ups"),
    ]

    static let barbellRow = [
        barbell("barbell-bent-over-row"), dumbbell("dumbbell-single-arm-row"), band("band-row"), bodyweight("inverted-row"),
    ]
    static let cableRow = [
        cable("machine-seated-cable-row"), dumbbell("chest-supported-dumbbell-row"), band("band-row"), bodyweight("inverted-row"),
    ]
    static let latPulldown = [
        cable("wide-grip-lat-pulldown"), bar("pull-ups"), band("band-kneeling-pulldown"), bodyweight("inverted-row"),
    ]
    static let pullUp = [
        bar("pull-ups"), cable("wide-grip-lat-pulldown"), band("band-kneeling-pulldown"), bodyweight("inverted-row"),
    ]
    static let curl = [dumbbell("dumbbell-curl"), band("band-curl")]
    static let hammerCurl = [dumbbell("dumbbell-hammer-curl"), band("band-curl")]

    static let cableCrunch = [cable("kneeling-cable-crunch"), bodyweight("crunches")]
    static let plank = [option("front-plank", .duration, [])]
    static let deadBug = [bodyweight("dead-bug")]

    static func main(_ options: [ExerciseOption], _ sets: Int = 3) -> ProgramExercise {
        ProgramExercise(options: options, role: .main, sets: sets)
    }

    static func secondary(_ options: [ExerciseOption], _ sets: Int = 3) -> ProgramExercise {
        ProgramExercise(options: options, role: .secondary, sets: sets)
    }

    static func isolation(_ options: [ExerciseOption], _ sets: Int = 3) -> ProgramExercise {
        ProgramExercise(options: options, role: .isolation, sets: sets)
    }

    // MARK: Osnovni full body (1–2 dana)

    static let basicA = ProgramWorkout(key: "basicA", name: "Cijelo tijelo A", exercises: [
        main(squat),
        main(benchPress),
        secondary(cableRow),
        secondary(romanianDeadlift),
        isolation(lateralRaise, 2),
        isolation(plank, 2),
    ])

    static let basicB = ProgramWorkout(key: "basicB", name: "Cijelo tijelo B", exercises: [
        main(hipThrust),
        main(dumbbellOverheadPress),
        secondary(latPulldown),
        secondary(splitSquat),
        secondary(inclinePress, 2),
        isolation(deadBug, 2),
    ])

    // MARK: Početnički full body A/B (3 dana)

    static let beginnerA = ProgramWorkout(key: "beginnerA", name: "Cijelo tijelo A", exercises: [
        main(squat),
        main(benchPress),
        secondary(barbellRow),
        isolation(tricepsPushdown, 2),
        isolation(plank, 2),
    ])

    static let beginnerB = ProgramWorkout(key: "beginnerB", name: "Cijelo tijelo B", exercises: [
        main(deadlift),
        main(overheadPress),
        secondary(latPulldown),
        secondary(inclinePress, 2),
        isolation(curl, 2),
    ])

    // MARK: Full body A/B/C (3 dana)

    static let fullBodyA = ProgramWorkout(key: "fullA", name: "Cijelo tijelo A", exercises: [
        main(squat),
        main(benchPress),
        secondary(barbellRow),
        isolation(legCurl),
        isolation(lateralRaise),
        isolation(tricepsPushdown, 2),
    ])

    static let fullBodyB = ProgramWorkout(key: "fullB", name: "Cijelo tijelo B", exercises: [
        main(romanianDeadlift),
        secondary(inclinePress),
        secondary(latPulldown),
        secondary(legPress),
        isolation(curl),
        isolation(calfRaise),
    ])

    static let fullBodyC = ProgramWorkout(key: "fullC", name: "Cijelo tijelo C", exercises: [
        main(overheadPress),
        secondary(splitSquat),
        secondary(cableRow),
        secondary(hipThrust),
        isolation(chestFly),
        isolation(cableCrunch, 2),
    ])

    // MARK: Upper/Lower (4 dana)

    static let upperA = ProgramWorkout(key: "upperA", name: "Gornji dio tijela A", exercises: [
        main(benchPress),
        main(barbellRow),
        secondary(inclinePress),
        secondary(latPulldown),
        isolation(lateralRaise),
        isolation(tricepsPushdown, 2),
    ])

    static let upperB = ProgramWorkout(key: "upperB", name: "Gornji dio tijela B", exercises: [
        main(overheadPress),
        main(pullUp),
        secondary(dumbbellPress),
        secondary(cableRow),
        isolation(curl),
        isolation(chestFly, 2),
    ])

    static let lowerA = ProgramWorkout(key: "lowerA", name: "Donji dio tijela A", exercises: [
        main(squat, 4),
        secondary(romanianDeadlift),
        secondary(splitSquat),
        isolation(legCurl),
        isolation(calfRaise),
        isolation(plank, 2),
    ])

    static let lowerB = ProgramWorkout(key: "lowerB", name: "Donji dio tijela B", exercises: [
        main(deadlift),
        secondary(legPress),
        secondary(hipThrust),
        isolation(legExtension),
        isolation(calfRaise),
        isolation(cableCrunch),
    ])

    // MARK: Push/Pull/Legs

    static let pushA = ProgramWorkout(key: "pushA", name: "Push A", exercises: [
        main(benchPress, 4),
        secondary(dumbbellOverheadPress),
        secondary(inclinePress),
        isolation(lateralRaise),
        isolation(tricepsPushdown),
    ])

    static let pushB = ProgramWorkout(key: "pushB", name: "Push B", exercises: [
        main(overheadPress, 4),
        secondary(dumbbellPress),
        isolation(chestFly),
        isolation(lateralRaise),
        isolation(tricepsExtension),
    ])

    static let pullA = ProgramWorkout(key: "pullA", name: "Pull A", exercises: [
        main(pullUp),
        main(barbellRow, 4),
        secondary(cableRow),
        isolation(facePull),
        isolation(curl),
    ])

    static let pullB = ProgramWorkout(key: "pullB", name: "Pull B", exercises: [
        main(latPulldown, 4),
        secondary(cableRow),
        secondary(barbellRow),
        isolation(facePull),
        isolation(hammerCurl),
    ])

    static let legsA = ProgramWorkout(key: "legsA", name: "Noge A", exercises: [
        main(squat, 4),
        secondary(romanianDeadlift),
        secondary(legPress),
        isolation(legCurl),
        isolation(calfRaise, 4),
    ])

    static let legsB = ProgramWorkout(key: "legsB", name: "Noge B", exercises: [
        main(deadlift),
        secondary(splitSquat),
        secondary(hipThrust),
        isolation(legExtension),
        isolation(calfRaise, 4),
        isolation(cableCrunch),
    ])
}
