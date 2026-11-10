package com.brunodobric.gymapp.ui.exercises

import androidx.annotation.StringRes
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.catalog.ExerciseCategory
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.ExerciseKind
import com.brunodobric.gymapp.catalog.Muscle

// Nazivi za prikaz, kao App/Exercises/ExerciseLabels.swift. Ključevi u katalogu ostaju engleski.

@StringRes
internal fun categoryTitle(category: ExerciseCategory): Int = when (category) {
    ExerciseCategory.CHEST -> R.string.category_chest
    ExerciseCategory.BACK -> R.string.category_back
    ExerciseCategory.SHOULDERS -> R.string.category_shoulders
    ExerciseCategory.ARMS -> R.string.category_arms
    ExerciseCategory.LEGS -> R.string.category_legs
    ExerciseCategory.CORE -> R.string.category_core
    ExerciseCategory.CARDIO -> R.string.category_cardio
}

@StringRes
internal fun kindTitle(kind: ExerciseKind): Int = when (kind) {
    ExerciseKind.WARM_UP -> R.string.kind_warm_up
    ExerciseKind.STRENGTH -> R.string.kind_strength
    ExerciseKind.STRETCHING -> R.string.kind_stretching
    ExerciseKind.CARDIO -> R.string.kind_cardio
}

@StringRes
internal fun muscleTitle(muscle: Muscle): Int = when (muscle) {
    Muscle.CHEST -> R.string.muscle_chest
    Muscle.SHOULDERS -> R.string.muscle_shoulders
    Muscle.TRICEPS -> R.string.muscle_triceps
    Muscle.BICEPS -> R.string.muscle_biceps
    Muscle.FOREARMS -> R.string.muscle_forearms
    Muscle.LATS -> R.string.muscle_lats
    Muscle.MIDDLE_BACK -> R.string.muscle_middle_back
    Muscle.LOWER_BACK -> R.string.muscle_lower_back
    Muscle.TRAPS -> R.string.muscle_traps
    Muscle.NECK -> R.string.muscle_neck
    Muscle.QUADRICEPS -> R.string.muscle_quadriceps
    Muscle.HAMSTRINGS -> R.string.muscle_hamstrings
    Muscle.GLUTES -> R.string.muscle_glutes
    Muscle.CALVES -> R.string.muscle_calves
    Muscle.ADDUCTORS -> R.string.muscle_adductors
    Muscle.ABDUCTORS -> R.string.muscle_abductors
    Muscle.ABDOMINALS -> R.string.muscle_abdominals
}

@StringRes
internal fun equipmentTitle(equipment: Equipment): Int = when (equipment) {
    Equipment.BARBELL -> R.string.equipment_barbell
    Equipment.EZ_BAR -> R.string.equipment_ez_bar
    Equipment.DUMBBELL -> R.string.equipment_dumbbell
    Equipment.CABLE -> R.string.equipment_cable
    Equipment.MACHINE -> R.string.equipment_machine
    Equipment.BODYWEIGHT -> R.string.equipment_bodyweight
    Equipment.KETTLEBELL -> R.string.equipment_kettlebell
    Equipment.BANDS -> R.string.equipment_bands
    Equipment.OTHER -> R.string.equipment_other
}

@StringRes
internal fun inputTypeTitle(type: ExerciseInputType): Int = when (type) {
    ExerciseInputType.WEIGHT_REPS -> R.string.input_weight_reps
    ExerciseInputType.BODYWEIGHT -> R.string.input_bodyweight
    ExerciseInputType.WEIGHTED_BODYWEIGHT -> R.string.input_weighted_bodyweight
    ExerciseInputType.ASSISTED -> R.string.input_assisted
    ExerciseInputType.DURATION -> R.string.input_duration
    ExerciseInputType.DURATION_DISTANCE -> R.string.input_duration_distance
}
