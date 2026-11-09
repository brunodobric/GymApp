package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.catalog.ExerciseInputType

// Sadržaj gotovih programa: izvedbe vježbi po opremi, obrasci kretanja i treninzi (isto kao
// ProgramContent.swift). Volumen (tjedne serije po mišiću) i učestalost provjeravaju testovi u `ProgramTest`.
internal object ProgramContent {

    // MARK: Izvedbe

    private fun option(id: String, input: ExerciseInputType, equipment: Set<Equipment>) = ExerciseOption(id, input, equipment)
    private fun barbell(id: String) = option(id, ExerciseInputType.WEIGHT_REPS, setOf(Equipment.BARBELL))
    private fun dumbbell(id: String) = option(id, ExerciseInputType.WEIGHT_REPS, setOf(Equipment.DUMBBELL))
    private fun cable(id: String) = option(id, ExerciseInputType.WEIGHT_REPS, setOf(Equipment.CABLE))
    private fun machine(id: String) = option(id, ExerciseInputType.WEIGHT_REPS, setOf(Equipment.MACHINE))
    private fun band(id: String) = option(id, ExerciseInputType.WEIGHT_REPS, setOf(Equipment.BANDS))
    private fun bodyweight(id: String) = option(id, ExerciseInputType.BODYWEIGHT, emptySet())

    /** Zgibovi i slično: treba šipka. */
    private fun bar(id: String) = option(id, ExerciseInputType.BODYWEIGHT, setOf(Equipment.OTHER))

    // MARK: Obrasci kretanja

    val squat = listOf(barbell("barbell-squat"), dumbbell("dumbbell-goblet-squat"), bodyweight("bodyweight-squat"))
    val legPress = listOf(
        machine("machine-leg-press"), dumbbell("dumbbell-bulgarian-split-squat"), bodyweight("bulgarian-split-squat"),
    )
    val splitSquat = listOf(dumbbell("dumbbell-bulgarian-split-squat"), bodyweight("bulgarian-split-squat"))
    val deadlift = listOf(barbell("barbell-deadlift"), dumbbell("dumbbell-deadlift"), bodyweight("single-leg-hip-thrust"))
    val romanianDeadlift = listOf(
        barbell("barbell-romanian-deadlift"), dumbbell("dumbbell-stiff-leg-deadlift"), band("band-romanian-deadlift"),
        bodyweight("single-leg-hip-thrust"),
    )
    val hipThrust = listOf(
        barbell("barbell-hip-thrust"), dumbbell("dumbbell-heels-elevated-hip-thrust"), bodyweight("glute-bridge"),
    )
    val legCurl = listOf(
        machine("lying-leg-curl"), dumbbell("dumbbell-leg-curl"), band("band-leg-curl"), bodyweight("towel-slide-leg-curl"),
    )
    val legExtension = listOf(machine("machine-leg-extension"))
    val calfRaise = listOf(
        machine("standing-calf-raise-machine"), dumbbell("dumbbell-single-leg-calf-raise"),
        bodyweight("single-leg-standing-calf-raise"),
    )

    val benchPress = listOf(barbell("barbell-bench-press"), dumbbell("dumbbell-bench-press"), bodyweight("push-up"))
    val dumbbellPress = listOf(dumbbell("dumbbell-bench-press"), machine("machine-chest-press"), bodyweight("push-up"))
    val inclinePress = listOf(dumbbell("dumbbell-incline-bench-press"), bodyweight("push-up"))
    val overheadPress = listOf(
        barbell("barbell-overhead-press"), dumbbell("dumbbell-seated-overhead-press"), band("band-overhead-press"),
        bodyweight("pike-push-up"),
    )
    val dumbbellOverheadPress = listOf(
        dumbbell("dumbbell-seated-overhead-press"), band("band-overhead-press"), bodyweight("pike-push-up"),
    )
    val chestFly = listOf(cable("cable-pec-fly"), dumbbell("dumbbell-chest-fly"))
    val lateralRaise = listOf(dumbbell("dumbbell-lateral-raise"), band("band-lateral-raise"))
    val facePull = listOf(cable("machine-face-pulls"), band("band-high-face-pull"), dumbbell("dumbbell-rear-delt-fly"))
    val tricepsPushdown = listOf(
        cable("cable-bar-pushdown"), dumbbell("dumbbell-seated-overhead-tricep-extension"), bodyweight("bench-dips"),
    )
    val tricepsExtension = listOf(
        dumbbell("dumbbell-skullcrusher"), cable("cable-bar-pushdown"), bodyweight("diamond-push-ups"),
    )

    val barbellRow = listOf(
        barbell("barbell-bent-over-row"), dumbbell("dumbbell-single-arm-row"), band("band-row"), bodyweight("inverted-row"),
    )
    val cableRow = listOf(
        cable("machine-seated-cable-row"), dumbbell("chest-supported-dumbbell-row"), band("band-row"), bodyweight("inverted-row"),
    )
    val latPulldown = listOf(
        cable("wide-grip-lat-pulldown"), bar("pull-ups"), band("band-kneeling-pulldown"), bodyweight("inverted-row"),
    )
    val pullUp = listOf(
        bar("pull-ups"), cable("wide-grip-lat-pulldown"), band("band-kneeling-pulldown"), bodyweight("inverted-row"),
    )
    val curl = listOf(dumbbell("dumbbell-curl"), band("band-curl"))
    val hammerCurl = listOf(dumbbell("dumbbell-hammer-curl"), band("band-curl"))

    val cableCrunch = listOf(cable("kneeling-cable-crunch"), bodyweight("crunches"))
    val plank = listOf(option("front-plank", ExerciseInputType.DURATION, emptySet()))
    val deadBug = listOf(bodyweight("dead-bug"))

    private fun main(options: List<ExerciseOption>, sets: Int = 3) = ProgramExercise(options, ExerciseRole.MAIN, sets)
    private fun secondary(options: List<ExerciseOption>, sets: Int = 3) = ProgramExercise(options, ExerciseRole.SECONDARY, sets)
    private fun isolation(options: List<ExerciseOption>, sets: Int = 3) = ProgramExercise(options, ExerciseRole.ISOLATION, sets)

    // MARK: Osnovni full body (1–2 dana)

    val basicA = ProgramWorkout(
        "basicA", "Cijelo tijelo A",
        listOf(
            main(squat), main(benchPress), secondary(cableRow), secondary(romanianDeadlift),
            isolation(lateralRaise, 2), isolation(plank, 2),
        ),
    )

    val basicB = ProgramWorkout(
        "basicB", "Cijelo tijelo B",
        listOf(
            main(hipThrust), main(dumbbellOverheadPress), secondary(latPulldown), secondary(splitSquat),
            secondary(inclinePress, 2), isolation(deadBug, 2),
        ),
    )

    // MARK: Početnički full body A/B (3 dana)

    val beginnerA = ProgramWorkout(
        "beginnerA", "Cijelo tijelo A",
        listOf(main(squat), main(benchPress), secondary(barbellRow), isolation(tricepsPushdown, 2), isolation(plank, 2)),
    )

    val beginnerB = ProgramWorkout(
        "beginnerB", "Cijelo tijelo B",
        listOf(main(deadlift), main(overheadPress), secondary(latPulldown), secondary(inclinePress, 2), isolation(curl, 2)),
    )

    // MARK: Full body A/B/C (3 dana)

    val fullBodyA = ProgramWorkout(
        "fullA", "Cijelo tijelo A",
        listOf(
            main(squat), main(benchPress), secondary(barbellRow), isolation(legCurl), isolation(lateralRaise),
            isolation(tricepsPushdown, 2),
        ),
    )

    val fullBodyB = ProgramWorkout(
        "fullB", "Cijelo tijelo B",
        listOf(
            main(romanianDeadlift), secondary(inclinePress), secondary(latPulldown), secondary(legPress),
            isolation(curl), isolation(calfRaise),
        ),
    )

    val fullBodyC = ProgramWorkout(
        "fullC", "Cijelo tijelo C",
        listOf(
            main(overheadPress), secondary(splitSquat), secondary(cableRow), secondary(hipThrust),
            isolation(chestFly), isolation(cableCrunch, 2),
        ),
    )

    // MARK: Upper/Lower (4 dana)

    val upperA = ProgramWorkout(
        "upperA", "Gornji dio tijela A",
        listOf(
            main(benchPress), main(barbellRow), secondary(inclinePress), secondary(latPulldown),
            isolation(lateralRaise), isolation(tricepsPushdown, 2),
        ),
    )

    val upperB = ProgramWorkout(
        "upperB", "Gornji dio tijela B",
        listOf(
            main(overheadPress), main(pullUp), secondary(dumbbellPress), secondary(cableRow),
            isolation(curl), isolation(chestFly, 2),
        ),
    )

    val lowerA = ProgramWorkout(
        "lowerA", "Donji dio tijela A",
        listOf(
            main(squat, 4), secondary(romanianDeadlift), secondary(splitSquat), isolation(legCurl),
            isolation(calfRaise), isolation(plank, 2),
        ),
    )

    val lowerB = ProgramWorkout(
        "lowerB", "Donji dio tijela B",
        listOf(
            main(deadlift), secondary(legPress), secondary(hipThrust), isolation(legExtension),
            isolation(calfRaise), isolation(cableCrunch),
        ),
    )

    // MARK: Push/Pull/Legs

    val pushA = ProgramWorkout(
        "pushA", "Push A",
        listOf(
            main(benchPress, 4), secondary(dumbbellOverheadPress), secondary(inclinePress),
            isolation(lateralRaise), isolation(tricepsPushdown),
        ),
    )

    val pushB = ProgramWorkout(
        "pushB", "Push B",
        listOf(
            main(overheadPress, 4), secondary(dumbbellPress), isolation(chestFly), isolation(lateralRaise),
            isolation(tricepsExtension),
        ),
    )

    val pullA = ProgramWorkout(
        "pullA", "Pull A",
        listOf(main(pullUp), main(barbellRow, 4), secondary(cableRow), isolation(facePull), isolation(curl)),
    )

    val pullB = ProgramWorkout(
        "pullB", "Pull B",
        listOf(main(latPulldown, 4), secondary(cableRow), secondary(barbellRow), isolation(facePull), isolation(hammerCurl)),
    )

    val legsA = ProgramWorkout(
        "legsA", "Noge A",
        listOf(main(squat, 4), secondary(romanianDeadlift), secondary(legPress), isolation(legCurl), isolation(calfRaise, 4)),
    )

    val legsB = ProgramWorkout(
        "legsB", "Noge B",
        listOf(
            main(deadlift), secondary(splitSquat), secondary(hipThrust), isolation(legExtension),
            isolation(calfRaise, 4), isolation(cableCrunch),
        ),
    )
}
