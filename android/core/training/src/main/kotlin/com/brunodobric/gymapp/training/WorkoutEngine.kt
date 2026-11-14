package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.model.moveElements
import com.brunodobric.gymapp.units.WeightUnit
import java.time.Instant
import java.util.UUID

sealed class WorkoutError(message: String) : Exception(message) {
    /** Već postoji trening u tijeku. */
    data object AlreadyActive : WorkoutError("Trening je već u tijeku")

    /** Serija nema sve potrebne vrijednosti za svoju vrstu unosa. */
    data object SetIncomplete : WorkoutError("Serija nije potpuna")

    /** Trening nema nijednu završenu seriju. */
    data object NothingCompleted : WorkoutError("Nema završenih serija")

    data object NeedsTwoExercises : WorkoutError("Superset traži dvije vježbe")
}

data class WorkoutSummary(
    val durationSeconds: Double,
    val totalVolumeKg: Double,
    val completedSets: Int,
    /** Tvrde serije ([SetMetrics.isHard]): radne serije bez preslabih. */
    val hardSets: Int,
    /** Svi rekordi treninga po vježbi. */
    val records: List<ExerciseRecords>,
    /** Najviše tri istaknuta rekorda ([PRRanking]), od najznačajnijeg. */
    val highlights: List<RecordHighlight>,
    /** Rekordi koji nisu istaknuti ("i još 4 manja rekorda"). */
    val otherRecordsCount: Int,
    /** Kardio vježbe u treningu snage; null bez njih. */
    val cardio: CardioPart? = null,
) {
    data class ExerciseRecords(val exerciseKey: String, val exerciseName: String, val records: List<PersonalRecord>)
}

/** Obrisana serija, zapamćena dok korisnik ne potvrdi brisanje (traka "Poništi"). */
data class RemovedSet(
    val id: UUID,
    /** Mjesto serije u vježbi prije brisanja. */
    val position: Int,
    val values: SetValues,
    val completedAt: Instant?,
)

/**
 * Operacije nad aktivnim treningom. Svaka promjena odmah se sprema (oporavak prekinutog treninga),
 * pa gašenje aplikacije usred treninga ne gubi ništa.
 */
class WorkoutEngine(val store: GymStore) {

    // MARK: Trening

    fun startSession(
        name: String,
        kind: WorkoutKind = WorkoutKind.STRENGTH,
        device: DeviceRole = DeviceRole.PHONE,
        templateId: UUID? = null,
        scheduleId: UUID? = null,
        now: Instant = Instant.now(),
    ): Session {
        if (store.activeSession() != null) throw WorkoutError.AlreadyActive
        val session = Session(name, kind, now)
        session.controllingDevice = device
        session.templateId = templateId
        session.scheduleId = scheduleId
        session.lastActivityAt = now
        store.insert(session)
        store.save()
        return session
    }

    /**
     * Zatvara trening: briše nezavršene serije, prazne i izbačene vježbe. Trening bez ijedne završene serije
     * ne može se spremiti (nudi se odbacivanje).
     */
    fun finishSession(session: Session, notes: String? = null, now: Instant = Instant.now()) {
        val hasCompleted = session.exercises.any { exercise -> !exercise.isRemoved && exercise.sets.any { it.isCompleted } }
        if (!hasCompleted) throw WorkoutError.NothingCompleted

        for (exercise in session.exercises.toList()) {
            if (exercise.isRemoved) {
                store.delete(exercise)
                continue
            }
            exercise.sets.filter { !it.isCompleted }.forEach(store::delete)
            if (exercise.sets.none { it.isCompleted }) store.delete(exercise)
        }
        // Kardio: ukupna udaljenost treninga iz završenih serija (ručni unos).
        val distance = session.exercises.flatMap { it.sets }.filter { it.isCompleted }.mapNotNull { it.distanceMeters }.sum()
        if (distance > 0) session.distanceMeters = distance
        if (notes != null) session.notes = notes
        session.state = SessionState.FINISHED
        session.endedAt = now
        session.restTimerStartedAt = null
        session.restTimerEndsAt = null
        session.lastActivityAt = now
        store.save()
    }

    /** Odbacivanje briše trening u cijelosti (i njegove vježbe i serije). */
    fun discardSession(session: Session) {
        store.delete(session)
        store.save()
    }

    /** Zatvara zaboravljeni trening na predloženi kraj (zadnja završena serija). */
    fun closeStaleSession(session: Session, now: Instant = Instant.now()) {
        val assessment = RecoveryAssessment.assess(session.startedAt, session.lastActivityAt, lastCompletedSetAt(session), now)
        finishSession(session, now = assessment.suggestedEnd)
    }

    fun lastCompletedSetAt(session: Session): Instant? =
        session.exercises.flatMap { it.sets }.mapNotNull { it.completedAt }.maxOrNull()

    // MARK: Vježbe

    /**
     * Dodaje vježbu i stvara serije prema planu ([SetPlanner]): bez ciljeva onoliko zagrijavanja koliko je bilo
     * prošli put i najčešći broj radnih serija iz zadnjih izvođenja, s pretpunjenim vrijednostima, a bez povijesti
     * tri prazne radne serije. Ciljevi predloška određuju serije i ponavljanja, a uz korak težine plan predlaže
     * veću težinu kad je prošli put dosegnuta gornja granica raspona.
     */
    fun addExercise(
        ref: ExerciseRef,
        inputType: ExerciseInputType,
        session: Session,
        restSeconds: Int? = null,
        now: Instant = Instant.now(),
        targets: List<SetTarget> = emptyList(),
        weightStep: Double? = null,
        unit: WeightUnit = WeightUnit.KILOGRAMS,
    ): SessionExercise {
        val order = (session.exercises.maxOfOrNull { it.orderIndex } ?: -1) + 1
        val exercise = session.add(SessionExercise(order, ref, inputType))
        exercise.restSeconds = restSeconds

        val performances = previousPerformances(ref, session)
        val plan = SetPlanner.plan(
            previous = performances.firstOrNull().orEmpty(),
            recentWorkingCounts = performances.take(SmartDefaults.RECENT_PERFORMANCE_COUNT)
                .map { sets -> sets.count { it.kind == SetKind.WORKING } },
            targets = targets,
            inputType = inputType,
            weightStep = weightStep,
            unit = unit,
        )
        plan.sets.forEachIndexed { index, values -> exercise.add(SetLog(index, values.kind)).fill(values) }
        exercise.targetRepsMin = plan.repRange?.lower
        exercise.targetRepsMax = plan.repRange?.upper
        exercise.loadChangeKg = plan.loadChangeKg
        touch(session, now)
        return exercise
    }

    /**
     * Zamjenjuje vježbu u treningu drugom (zauzeta sprava). Bez završenih serija vježba se mijenja na istom mjestu,
     * s istim brojem serija i vrijednostima iz povijesti nove vježbe. Sa završenim serijama stara vježba ostaje samo
     * sa završenima, a nova dolazi odmah iza nje s preostalim serijama (barem jednom). Superset i pauza ostaju.
     */
    fun replaceExercise(
        exercise: SessionExercise,
        ref: ExerciseRef,
        inputType: ExerciseInputType,
        now: Instant = Instant.now(),
    ): SessionExercise {
        val session = exercise.session ?: return exercise
        val sets = exercise.orderedSets
        val done = sets.filter { it.isCompleted }
        val pending = sets.filter { !it.isCompleted }
        val visible = visibleExercises(session).toMutableList()
        val removed = removedExercises(session)

        val created = session.add(SessionExercise(exercise.orderIndex, ref, inputType))
        created.restSeconds = exercise.restSeconds
        created.supersetGroupId = exercise.supersetGroupId

        val previous = previousPerformances(ref, session).firstOrNull().orEmpty()
        val kinds = if (pending.isEmpty()) listOf(SetKind.WORKING) else pending.map { it.kind }
        val made = mutableListOf<SetValues>()
        kinds.forEachIndexed { index, kind ->
            val position = made.count { it.kind == kind }
            val values = SmartDefaults.defaults(position, kind, previous) ?: SetValues(kind)
            made += values
            created.add(SetLog(index, kind)).fill(values)
        }

        val index = visible.indexOfFirst { it.id == exercise.id }.takeIf { it >= 0 } ?: (visible.size - 1).coerceAtLeast(0)
        if (done.isEmpty()) {
            if (index < visible.size) visible[index] = created else visible += created
            store.delete(exercise)
        } else {
            pending.forEach(store::delete)
            done.forEachIndexed { position, set -> set.orderIndex = position }
            visible.add(minOf(index + 1, visible.size), created)
        }
        (visible + removed).forEachIndexed { position, item -> item.orderIndex = position }
        touch(session, now)
        return created
    }

    fun addSet(exercise: SessionExercise, kind: SetKind = SetKind.WORKING, now: Instant = Instant.now()): SetLog {
        val previous = previousSets(exercise.exercise, exercise.session)
        // Zagrijavanje ide ispred prve neodrađene serije (ili na kraj kad su sve odrađene).
        val set = appendSet(exercise, kind, previous, beforeIncomplete = kind == SetKind.WARM_UP)
        exercise.session?.let { touch(it, now) }
        return set
    }

    /** Briše seriju i vraća njezinu snimku, da se brisanje može poništiti ([restoreSet]). */
    fun removeSet(set: SetLog, now: Instant = Instant.now()): RemovedSet {
        val removed = RemovedSet(set.id, set.orderIndex, set.values, set.completedAt)
        val exercise = set.exercise
        store.delete(set)
        exercise?.orderedSets?.forEachIndexed { index, remaining -> remaining.orderIndex = index }
        val session = exercise?.session
        if (session != null) touch(session, now) else store.save()
        return removed
    }

    /** Vraća obrisanu seriju na njezino mjesto, s istim vrijednostima i oznakom završetka. */
    fun restoreSet(removed: RemovedSet, exercise: SessionExercise, now: Instant = Instant.now()): SetLog {
        val sets = exercise.orderedSets.toMutableList()
        val set = SetLog(removed.id)
        set.kind = removed.values.kind
        set.weightKg = removed.values.weightKg
        set.reps = removed.values.reps
        set.extraWeightKg = removed.values.extraWeightKg
        set.durationSeconds = removed.values.durationSeconds
        set.distanceMeters = removed.values.distanceMeters
        set.rpe = removed.values.rpe
        set.completedAt = removed.completedAt
        exercise.add(set)
        sets.add(removed.position.coerceIn(0, sets.size), set)
        sets.forEachIndexed { index, item -> item.orderIndex = index }
        val session = exercise.session
        if (session != null) touch(session, now) else store.save()
        return set
    }

    /** Izbacivanje se može poništiti do kraja treninga ([restoreExercise]). */
    fun removeExercise(exercise: SessionExercise, now: Instant = Instant.now()) {
        exercise.isRemoved = true
        exercise.session?.let { touch(it, now) }
    }

    fun restoreExercise(exercise: SessionExercise, now: Instant = Instant.now()) {
        exercise.isRemoved = false
        val session = exercise.session ?: return
        exercise.orderIndex = (session.exercises.maxOfOrNull { it.orderIndex } ?: -1) + 1
        touch(session, now)
    }

    fun removedExercises(session: Session): List<SessionExercise> = session.orderedExercises.filter { it.isRemoved }

    fun visibleExercises(session: Session): List<SessionExercise> = session.orderedExercises.filter { !it.isRemoved }

    /** Drag & drop: premješta vidljive vježbe, izbačene ostaju na kraju. */
    fun moveExercises(session: Session, from: Collection<Int>, to: Int, now: Instant = Instant.now()) {
        val visible = visibleExercises(session).toMutableList()
        visible.moveElements(from, to)
        (visible + removedExercises(session)).forEachIndexed { index, exercise -> exercise.orderIndex = index }
        touch(session, now)
    }

    // MARK: Supersetovi

    /** Spaja vježbe u superset i postavlja ih jednu do druge, na mjesto prve među njima. */
    fun makeSuperset(exercises: List<SessionExercise>, session: Session, now: Instant = Instant.now()) {
        if (exercises.size < 2) throw WorkoutError.NeedsTwoExercises
        val group = UUID.randomUUID()
        val selected = exercises.map { it.id }.toSet()
        val ordered = visibleExercises(session)
        val anchor = ordered.indexOfFirst { it.id in selected }.takeIf { it >= 0 } ?: return
        val members = ordered.filter { it.id in selected }
        val others = ordered.filter { it.id !in selected }
        val insertAt = minOf(anchor, others.size)
        val result = others.subList(0, insertAt) + members + others.subList(insertAt, others.size)
        members.forEach { it.supersetGroupId = group }
        (result + removedExercises(session)).forEachIndexed { index, exercise -> exercise.orderIndex = index }
        touch(session, now)
    }

    fun removeFromSuperset(exercise: SessionExercise, now: Instant = Instant.now()) {
        val group = exercise.supersetGroupId
        exercise.supersetGroupId = null
        val session = exercise.session ?: return
        // Superset s jednom vježbom nema smisla.
        val rest = visibleExercises(session).filter { group != null && it.supersetGroupId == group }
        if (rest.size == 1) rest[0].supersetGroupId = null
        touch(session, now)
    }

    /** Vježbe u istom supersetu (ili sama vježba), po redoslijedu. */
    fun group(exercise: SessionExercise): List<SessionExercise> {
        val id = exercise.supersetGroupId
        val session = exercise.session
        if (id == null || session == null) return listOf(exercise)
        return visibleExercises(session).filter { it.supersetGroupId == id }
    }

    // MARK: Serije i rest timer

    /** Označava seriju završenom, uz istu zadanu pauzu za sve vježbe (demo podaci, testovi). */
    fun completeSet(set: SetLog, defaultRestSeconds: Int, now: Instant = Instant.now()): RestTimer? =
        completeSet(set, RestDefaults.uniform(defaultRestSeconds), { null }, now)

    /**
     * Označava seriju završenom i vraća rest timer koji treba pokrenuti (null kad je pauza 0). Vježba bez
     * vlastite pauze dobiva zadanu prema vrsti; [isCompound] prima ključ vježbe.
     */
    fun completeSet(
        set: SetLog,
        restDefaults: RestDefaults,
        isCompound: (String) -> Boolean?,
        now: Instant = Instant.now(),
    ): RestTimer? {
        val exercise = set.exercise ?: return null
        val session = exercise.session ?: return null
        if (!SetMetrics.isComplete(set.values, exercise.inputType)) throw WorkoutError.SetIncomplete
        set.completedAt = now

        val members = group(exercise)
        val position = members.indexOfFirst { it.id == exercise.id }.coerceAtLeast(0)
        val configured = exercise.restSeconds ?: members.lastOrNull()?.restSeconds
        val defaultSeconds = restDefaults.seconds(members.map { isCompound(it.exercise.key) })
        var seconds = RestPolicy.seconds(position, members.size, configured, defaultSeconds)
        if (set.kind == SetKind.WARM_UP) {
            val sets = exercise.orderedSets
            val next = sets.getOrNull(sets.indexOfFirst { it.id == set.id } + 1)
            seconds = RestPolicy.afterWarmUp(seconds, next?.kind == SetKind.WARM_UP)
        }
        val timer = if (seconds > 0) RestTimer(now, seconds) else null
        session.restTimerStartedAt = timer?.startedAt
        session.restTimerEndsAt = timer?.endsAt
        touch(session, now)
        return timer
    }

    fun uncompleteSet(set: SetLog, now: Instant = Instant.now()) {
        set.completedAt = null
        set.exercise?.session?.let { touch(it, now) }
    }

    fun restTimer(session: Session): RestTimer? {
        val start = session.restTimerStartedAt ?: return null
        val end = session.restTimerEndsAt ?: return null
        return RestTimer(start, end)
    }

    fun adjustRest(session: Session, deltaSeconds: Int, now: Instant = Instant.now()): RestTimer? {
        val adjusted = restTimer(session)?.adjusted(deltaSeconds, now) ?: return null
        session.restTimerEndsAt = adjusted.endsAt
        touch(session, now)
        return adjusted
    }

    fun cancelRest(session: Session, now: Instant = Instant.now()) {
        session.restTimerStartedAt = null
        session.restTimerEndsAt = null
        touch(session, now)
    }

    /** Sprema izmjenu (npr. težine ili ponavljanja) i bilježi aktivnost. */
    fun touch(session: Session, now: Instant = Instant.now()) {
        session.lastActivityAt = now
        store.save()
    }

    // MARK: Sažetak i rekordi

    /**
     * Sažetak treninga s osobnim rekordima. Rekordi se uspoređuju samo s ranije završenim treninzima.
     * @param excludedExercises ključevi vježbi isključenih iz rekorda
     * @param isCompound je li vježba (po ključu) složena, za rang istaknutih rekorda
     */
    fun summary(
        session: Session,
        trackedKinds: Set<PRKind> = PRKind.entries.toSet(),
        excludedExercises: Set<String> = emptySet(),
        isCompound: (String) -> Boolean? = { null },
        isCardio: (String) -> Boolean = { false },
        now: Instant = Instant.now(),
    ): WorkoutSummary {
        var volume = 0.0
        var completed = 0
        var hard = 0
        val records = mutableListOf<WorkoutSummary.ExerciseRecords>()
        val candidates = mutableListOf<RecordCandidate>()
        for (exercise in visibleExercises(session)) {
            val done = exercise.orderedSets.filter { it.isCompleted }.map { it.values }
            completed += done.size
            // Kardio nije tvrda serija: 20 minuta trake ne broji se uz serije snage.
            if (!isCardio(exercise.exerciseKey)) hard += done.count(SetMetrics::isHard)
            volume += done.sumOf { SetMetrics.volume(it, exercise.inputType) }

            val key = exercise.exerciseKey
            if (trackedKinds.isEmpty() || key in excludedExercises) continue
            val history = recordHistory(exercise.exercise, session, exercise.inputType)
            val found = PersonalRecordDetector.records(done, history, exercise.inputType, trackedKinds, session.startedAt)
            if (found.isNotEmpty()) {
                records += WorkoutSummary.ExerciseRecords(key, exercise.exerciseName, found)
                candidates += RecordCandidate(key, exercise.exerciseName, found, isCompound(key))
            }
        }
        val ranked = PRRanking.highlights(candidates)
        val end = session.endedAt ?: now
        return WorkoutSummary(
            durationSeconds = maxOf(0.0, secondsBetween(session.startedAt, end)),
            totalVolumeKg = volume,
            completedSets = completed,
            hardSets = hard,
            records = records,
            highlights = ranked.shown,
            otherRecordsCount = ranked.hiddenCount,
            cardio = SessionCardio.part(session, isCardio),
        )
    }

    // MARK: Pomoćno

    /** Dodaje seriju na kraj vježbe, ili ispred prve neodrađene serije kad je [beforeIncomplete] (zagrijavanje). */
    private fun appendSet(
        exercise: SessionExercise,
        kind: SetKind,
        previous: List<SetValues>,
        beforeIncomplete: Boolean = false,
    ): SetLog {
        val existing = exercise.orderedSets.toMutableList()
        val insertIndex = if (beforeIncomplete) {
            existing.indexOfFirst { !it.isCompleted }.takeIf { it >= 0 } ?: existing.size
        } else {
            existing.size
        }
        val before = existing.subList(0, insertIndex).toList()
        val position = before.count { it.kind == kind }
        val set = exercise.add(SetLog(insertIndex, kind))
        existing.add(insertIndex, set)
        existing.forEachIndexed { index, item -> item.orderIndex = index }

        var defaults = SmartDefaults.defaults(position, kind, previous)
        if (defaults == null) {
            // Bez povijesti nova serija preuzima vrijednosti prethodne serije iste vrste u ovom treningu.
            val last = before.lastOrNull { it.kind == kind } ?: existing.lastOrNull { it.kind == kind && it.id != set.id }
            if (last != null) defaults = SmartDefaults.defaults(0, kind, listOf(last.values))
        }
        if (defaults != null) {
            set.weightKg = defaults.weightKg
            set.reps = defaults.reps
            set.extraWeightKg = defaults.extraWeightKg
            set.durationSeconds = defaults.durationSeconds
            set.distanceMeters = defaults.distanceMeters
        }
        return set
    }

    /** Serije zadnjeg završenog izvođenja vježbe (izvor smart defaultsa), prvo u istom predlošku. */
    private fun previousSets(ref: ExerciseRef, session: Session?): List<SetValues> =
        previousPerformances(ref, session).firstOrNull().orEmpty()

    /**
     * Završene serije ranijih izvođenja vježbe, od najnovijeg. Kad je trening pokrenut iz predloška, izvođenja iz
     * istog predloška dolaze prva (teški i lagani dan s istom vježbom se ne miješaju).
     */
    fun previousPerformances(ref: ExerciseRef, session: Session?): List<List<SetValues>> {
        val all = finishedExercises(ref, session).mapNotNull { exercise ->
            val sets = exercise.orderedSets.filter { it.isCompleted }.map { it.values }
            if (sets.isEmpty()) null else exercise.session?.templateId to sets
        }
        val templateId = session?.templateId ?: return all.map { it.second }
        return all.filter { it.first == templateId }.map { it.second } + all.filter { it.first != templateId }.map { it.second }
    }

    /** Ranija izvođenja vježbe za rekorde, od najstarijeg prema najnovijem, s datumima treninga. */
    private fun recordHistory(ref: ExerciseRef, session: Session?, inputType: ExerciseInputType): RecordHistory {
        val history = RecordHistory()
        for (exercise in finishedExercises(ref, session).asReversed()) {
            history.add(exercise.orderedSets.filter { it.isCompleted }.map { it.values }, inputType, exercise.session?.startedAt)
        }
        return history
    }

    /** Izvođenja vježbe u ranije završenim treninzima, od najnovijeg prema starijem. */
    private fun finishedExercises(ref: ExerciseRef, session: Session?): List<SessionExercise> {
        val cutoff = session?.startedAt ?: Instant.MAX
        return store.finishedPerformances(ref.key).filter { exercise ->
            val owner = exercise.session
            owner != null && owner.id != session?.id && owner.startedAt < cutoff
        }
    }

    private fun SetLog.fill(values: SetValues) {
        weightKg = values.weightKg
        reps = values.reps
        extraWeightKg = values.extraWeightKg
        durationSeconds = values.durationSeconds
        distanceMeters = values.distanceMeters
    }

    companion object {
        /** Broj radnih serija koje se stvaraju za vježbu bez povijesti. */
        const val DEFAULT_WORKING_SETS = 3
    }
}
