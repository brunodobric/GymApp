package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.CycleOverride
import com.brunodobric.gymapp.model.CycleOverrideKind
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Schedule
import com.brunodobric.gymapp.model.ScheduleItem
import com.brunodobric.gymapp.model.ScheduleItemKind
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.TemplateExercise
import com.brunodobric.gymapp.model.WorkoutTemplate
import com.brunodobric.gymapp.model.moveElements
import java.util.UUID

/** Vježba kakva će biti u sljedećem treningu, nakon privremenih izmjena ciklusa. */
data class PlannedExercise(
    val source: UUID,
    val ref: ExerciseRef,
    val inputType: ExerciseInputType,
    /** Vježba je zamijenjena u ovom ciklusu (ciljevi originalne vježbe se ne primjenjuju). */
    val isReplacement: Boolean,
) {
    val id: UUID get() = source
}

/** Sljedeći trening koji "Započni" nudi za jedan raspored. */
data class PlannedWorkout(
    val schedule: Schedule,
    val item: ScheduleItem,
    val template: WorkoutTemplate,
    val cycle: Int,
    val exercises: List<PlannedExercise>,
)

/** Preskočeni trening tekućeg ciklusa, koji se može vratiti ([ScheduleEngine.unskip]). */
data class SkippedWorkout(val change: CycleOverride, val templateName: String) {
    val id: UUID get() = change.id
}

/**
 * Napredovanje kroz raspored. Osnova je redoslijed, ne kalendar: propušteni dan ništa ne pomiče.
 *
 * Sljedeći trening je prvi trening u nizu koji u tekućem ciklusu nije odrađen ni preskočen. Odrađeni
 * treninzi pamte se kao izmjene ciklusa (`completedWorkout`). `currentPosition` je indeks iza zadnjeg
 * odrađenog treninga prije prvog neodrađenog.
 */
class ScheduleEngine(private val store: GymStore) {

    // MARK: Rasporedi

    fun createSchedule(name: String, cycleCount: Int? = null): Schedule {
        val schedule = Schedule(name)
        schedule.cycleCount = cycleCount
        schedule.isActive = true
        store.insert(schedule)
        store.save()
        return schedule
    }

    fun addWorkout(template: WorkoutTemplate, schedule: Schedule): ScheduleItem =
        append(ScheduleItemKind.WORKOUT, template.id, schedule)

    /** Novi prazni trening (predložak) koji odmah ide na kraj niza. */
    fun addNewWorkout(name: String, schedule: Schedule): WorkoutTemplate {
        val template = TemplateEngine(store).createTemplate(name)
        addWorkout(template, schedule)
        return template
    }

    /** Umeće više treninga odjednom, redom kojim su zadani. Bez [index] idu na kraj niza. */
    fun insertWorkouts(templates: List<WorkoutTemplate>, schedule: Schedule, index: Int? = null): List<ScheduleItem> {
        recordLegacyProgress(schedule)
        val ordered = schedule.orderedItems.toMutableList()
        val position = (index ?: ordered.size).coerceIn(0, ordered.size)
        val added = templates.map { schedule.add(ScheduleItem(0, ScheduleItemKind.WORKOUT, it.id)) }
        ordered.addAll(position, added)
        ordered.forEachIndexed { order, item -> item.orderIndex = order }
        updatePosition(schedule, ordered)
        store.save()
        return added
    }

    fun addRestDay(schedule: Schedule): ScheduleItem = append(ScheduleItemKind.REST_DAY, null, schedule)

    /** Briše raspored zajedno s njegovim izmjenama ciklusa. */
    fun delete(schedule: Schedule) {
        deleteOverrides(schedule) { true }
        store.delete(schedule)
        store.save()
    }

    fun removeItem(item: ScheduleItem) {
        val schedule = item.schedule
        val removedIndex = schedule?.orderedItems?.indexOfFirst { it.id == item.id }
        store.delete(item)
        if (schedule != null) {
            schedule.orderedItems.forEachIndexed { index, remaining -> remaining.orderIndex = index }
            if (removedIndex != null && removedIndex >= 0 && removedIndex < schedule.currentPosition) schedule.currentPosition -= 1
        }
        store.save()
        if (schedule != null) rollIfCycleComplete(schedule)
    }

    /** Premješta stavke. Odrađeni treninzi ostaju odrađeni, a sljedeći je prvi neodrađeni u novom redoslijedu. */
    fun moveItems(schedule: Schedule, from: Collection<Int>, to: Int) {
        recordLegacyProgress(schedule)
        val ordered = schedule.orderedItems.toMutableList()
        ordered.moveElements(from, to)
        ordered.forEachIndexed { index, item -> item.orderIndex = index }
        updatePosition(schedule, ordered)
        store.save()
    }

    /** Pokreće raspored ispočetka (prvi ciklus, prva stavka). */
    fun restart(schedule: Schedule) {
        deleteOverrides(schedule) { true }
        schedule.currentCycle = 1
        schedule.currentPosition = 0
        schedule.isActive = true
        store.save()
        rollIfCycleComplete(schedule)
    }

    fun setActive(active: Boolean, schedule: Schedule) {
        schedule.isActive = active
        store.save()
    }

    // MARK: Što je sljedeće

    /** Indeks sljedećeg treninga (ne dana odmora, ne preskočenog) u tekućem ciklusu. */
    fun nextWorkoutIndex(schedule: Schedule): Int? {
        val items = schedule.orderedItems
        if (schedule.currentPosition >= items.size) return null
        val passed = passedItemIds(schedule, schedule.currentCycle)
        return (schedule.currentPosition until items.size).firstOrNull { index ->
            val item = items[index]
            item.kind == ScheduleItemKind.WORKOUT && item.id !in passed && isPlayable(item)
        }
    }

    /** Što "Započni" nudi: sljedeći neodrađeni trening aktivnog rasporeda. Stavke bez predloška se prelaze. */
    fun nextWorkout(schedule: Schedule): PlannedWorkout? {
        if (!schedule.isActive) return null
        val items = schedule.orderedItems
        val passed = passedItemIds(schedule, schedule.currentCycle)
        val changes = overrides(schedule, schedule.currentCycle)
        for (index in maxOf(schedule.currentPosition, 0) until items.size) {
            val item = items[index]
            if (item.kind != ScheduleItemKind.WORKOUT || item.id in passed) continue
            val template = item.workoutTemplateId?.let(store::template) ?: continue
            return PlannedWorkout(
                schedule, item, template, schedule.currentCycle,
                effectiveExercises(template, changes.filter { it.scheduleItemId == item.id }),
            )
        }
        return null
    }

    /**
     * Treninzi aktivnog rasporeda koje korisnik može pokrenuti umjesto sljedećeg, redom kao u nizu. Svaki
     * predložak je jednom: kad se ponavlja, uzima se prva stavka koja u ovom ciklusu još nije odrađena.
     */
    fun workoutChoices(schedule: Schedule): List<PlannedWorkout> {
        if (!schedule.isActive) return emptyList()
        val items = schedule.orderedItems
        val done = doneItemIds(schedule)
        val chosen = mutableMapOf<UUID, Int>()
        val order = mutableListOf<UUID>()
        items.forEachIndexed { index, item ->
            if (item.kind != ScheduleItemKind.WORKOUT) return@forEachIndexed
            val templateId = item.workoutTemplateId ?: return@forEachIndexed
            val existing = chosen[templateId]
            if (existing != null) {
                if (items[existing].id in done && item.id !in done) chosen[templateId] = index
            } else {
                chosen[templateId] = index
                order += templateId
            }
        }
        val changes = overrides(schedule, schedule.currentCycle)
        return order.mapNotNull { templateId ->
            val index = chosen[templateId] ?: return@mapNotNull null
            val template = store.template(templateId) ?: return@mapNotNull null
            if (TemplateStarter.startable(listOf(template)).isEmpty()) return@mapNotNull null
            val item = items[index]
            PlannedWorkout(schedule, item, template, schedule.currentCycle, effectiveExercises(template, changes.filter { it.scheduleItemId == item.id }))
        }
    }

    /** Sljedeći trening svakog aktivnog rasporeda. */
    fun upcomingWorkouts(): List<PlannedWorkout> = store.schedules.sortedBy { it.createdAt }.mapNotNull(::nextWorkout)

    // MARK: Napredovanje

    /**
     * Poziva se kad je trening završen. Bilježi trening kao odrađen u tekućem ciklusu: sljedeći trening ako je
     * to on, inače prvu još neodrađenu stavku s tim treningom. Vraća true kad je raspored napredovao.
     */
    fun sessionFinished(session: Session): Boolean {
        val schedule = session.scheduleId?.let(store::schedule) ?: return false
        val templateId = session.templateId ?: return false
        if (!schedule.isActive) return false
        val next = nextWorkoutIndex(schedule) ?: return false
        recordLegacyProgress(schedule)
        val items = schedule.orderedItems
        val passed = passedItemIds(schedule, schedule.currentCycle)
        val index = if (items[next].workoutTemplateId == templateId) {
            next
        } else {
            items.indices.firstOrNull {
                items[it].kind == ScheduleItemKind.WORKOUT && items[it].workoutTemplateId == templateId && items[it].id !in passed
            } ?: return false
        }
        store.insert(CycleOverride(schedule.id, schedule.currentCycle, items[index].id, CycleOverrideKind.COMPLETED_WORKOUT))
        updatePosition(schedule, items)
        store.save()
        rollIfCycleComplete(schedule)
        return true
    }

    /** Preskače sljedeći trening u ovom ciklusu. Poništava se s [unskip] dok raspored ne prođe tu stavku. */
    fun skipNextWorkout(schedule: Schedule): CycleOverride? {
        val index = nextWorkoutIndex(schedule) ?: return null
        val item = schedule.orderedItems[index]
        val change = store.insert(CycleOverride(schedule.id, schedule.currentCycle, item.id, CycleOverrideKind.SKIP_WORKOUT))
        store.save()
        rollIfCycleComplete(schedule)
        return change
    }

    /** Preskočeni treninzi tekućeg ciklusa, redom kao u nizu, s nazivom treninga. */
    fun skippedWorkouts(schedule: Schedule): List<SkippedWorkout> {
        val skips = overrides(schedule, schedule.currentCycle).filter { it.kind == CycleOverrideKind.SKIP_WORKOUT }
        return schedule.orderedItems.mapNotNull { item ->
            val change = skips.firstOrNull { it.scheduleItemId == item.id } ?: return@mapNotNull null
            SkippedWorkout(change, item.workoutTemplateId?.let(store::template)?.name ?: "")
        }
    }

    /** Vraća preskočeni trening. Moguće samo dok je ciklus još tekući. */
    fun unskip(change: CycleOverride, schedule: Schedule) {
        if (change.kind != CycleOverrideKind.SKIP_WORKOUT || change.cycleNumber != schedule.currentCycle) return
        recordLegacyProgress(schedule)
        store.delete(change)
        updatePosition(schedule, schedule.orderedItems)
        store.save()
    }

    // MARK: Privremene izmjene

    /** Izbacuje vježbu iz tekućeg ciklusa. Predložak i budući ciklusi ostaju nepromijenjeni. */
    fun removeExercise(exercise: TemplateExercise, planned: PlannedWorkout): CycleOverride {
        clearOverrides(exercise, planned)
        val change = CycleOverride(planned.schedule.id, planned.cycle, planned.item.id, CycleOverrideKind.REMOVE_EXERCISE)
        change.targetExerciseKey = exercise.exercise.key
        store.insert(change)
        store.save()
        return change
    }

    /** Zamjenjuje vježbu u tekućem ciklusu. */
    fun replaceExercise(exercise: TemplateExercise, ref: ExerciseRef, inputType: ExerciseInputType, planned: PlannedWorkout): CycleOverride {
        clearOverrides(exercise, planned)
        val change = CycleOverride(planned.schedule.id, planned.cycle, planned.item.id, CycleOverrideKind.REPLACE_EXERCISE)
        change.targetExerciseKey = exercise.exercise.key
        change.replacement = ref
        change.replacementInputType = inputType
        store.insert(change)
        store.save()
        return change
    }

    /** Poništava izmjenu (izbacivanje ili zamjenu). Preskakanje se poništava s [unskip]. */
    fun undo(change: CycleOverride) {
        store.delete(change)
        store.save()
    }

    /** Vježbe predloška nakon izmjena: izbačene nema, zamijenjene su zamijenjene. */
    fun effectiveExercises(template: WorkoutTemplate, overrides: List<CycleOverride>): List<PlannedExercise> =
        template.orderedExercises.mapNotNull { exercise ->
            val key = exercise.exercise.key
            val match = overrides.firstOrNull { it.targetExerciseKey == key && it.kind != CycleOverrideKind.SKIP_WORKOUT }
            val replacement = match?.replacement
            when {
                match?.kind == CycleOverrideKind.REMOVE_EXERCISE -> null
                match?.kind == CycleOverrideKind.REPLACE_EXERCISE && replacement != null ->
                    PlannedExercise(exercise.id, replacement, match.replacementInputType ?: exercise.inputType, isReplacement = true)
                else -> PlannedExercise(exercise.id, exercise.exercise, exercise.inputType, isReplacement = false)
            }
        }

    fun overrides(schedule: Schedule, cycle: Int): List<CycleOverride> =
        store.cycleOverrides.filter { it.scheduleId == schedule.id && it.cycleNumber == cycle }

    /** Odbacuje trening stvoren iz rasporeda ([addNewWorkout]) kad korisnik izađe bez spremanja. */
    fun discardNewWorkout(template: WorkoutTemplate, schedule: Schedule) {
        schedule.orderedItems.filter { it.workoutTemplateId == template.id }.forEach(::removeItem)
        TemplateEngine(store).delete(template)
    }

    // MARK: Pomoćno

    /** Briše izmjene rasporeda koje zadovoljavaju uvjet (bez spremanja). */
    private fun deleteOverrides(schedule: Schedule, shouldDelete: (CycleOverride) -> Boolean) {
        store.cycleOverrides.filter { it.scheduleId == schedule.id && shouldDelete(it) }.forEach(store::delete)
    }

    private fun clearOverrides(exercise: TemplateExercise, planned: PlannedWorkout) {
        val key = exercise.exercise.key
        overrides(planned.schedule, planned.cycle)
            .filter { it.scheduleItemId == planned.item.id && it.targetExerciseKey == key }
            .forEach(store::delete)
    }

    /**
     * Kad u ciklusu nema više treninga, počinje sljedeći; nakon zadnjeg ciklusa raspored postaje neaktivan.
     * Ciklus završava odmah nakon zadnjeg treninga, dani odmora na kraju niza se ne čekaju.
     */
    private fun rollIfCycleComplete(schedule: Schedule) {
        if (!schedule.isActive) return
        // Raspored bez ijednog treninga s postojećim predloškom nema ciklusa koji bi se mogli odraditi.
        if (schedule.orderedItems.none(::isPlayable)) return
        while (nextWorkoutIndex(schedule) == null) {
            val limit = schedule.cycleCount
            if (limit != null && schedule.currentCycle >= limit) {
                schedule.isActive = false
                schedule.currentPosition = schedule.orderedItems.size
                store.save()
                return
            }
            schedule.currentCycle += 1
            schedule.currentPosition = 0
            // Izmjene prošlih ciklusa više ništa ne mijenjaju, a inače bi se gomilale zauvijek.
            val current = schedule.currentCycle
            deleteOverrides(schedule) { it.cycleNumber < current }
            store.save()
        }
    }

    /** Stavka je trening čiji predložak još postoji. */
    private fun isPlayable(item: ScheduleItem): Boolean {
        if (item.kind != ScheduleItemKind.WORKOUT) return false
        return item.workoutTemplateId?.let(store::template) != null
    }

    private fun append(kind: ScheduleItemKind, templateId: UUID?, schedule: Schedule): ScheduleItem {
        val order = (schedule.items.maxOfOrNull { it.orderIndex } ?: -1) + 1
        val item = schedule.add(ScheduleItem(order, kind, templateId))
        store.save()
        return item
    }

    /** Stavke koje raspored u ciklusu prelazi: odrađene i preskočene. */
    private fun passedItemIds(schedule: Schedule, cycle: Int): Set<UUID> =
        overrides(schedule, cycle)
            .filter { it.kind == CycleOverrideKind.SKIP_WORKOUT || it.kind == CycleOverrideKind.COMPLETED_WORKOUT }
            .mapNotNull { it.scheduleItemId }.toSet()

    /** Treninzi odrađeni u tekućem ciklusu: zabilježeni i (iz starijih verzija) oni ispred pozicije. */
    private fun doneItemIds(schedule: Schedule): Set<UUID> {
        val recorded = overrides(schedule, schedule.currentCycle)
            .filter { it.kind == CycleOverrideKind.COMPLETED_WORKOUT }.mapNotNull { it.scheduleItemId }
        val items = schedule.orderedItems
        val beforePosition = items.take(minOf(schedule.currentPosition, items.size)).filter { it.kind == ScheduleItemKind.WORKOUT }.map { it.id }
        return (recorded + beforePosition).toSet()
    }

    /**
     * Starije verzije pamtile su napredak samo pozicijom. Prije promjene redoslijeda treninzi ispred pozicije
     * bilježe se kao odrađeni. Na Androidu se tako ponaša raspored iz uvezene sigurnosne kopije s iOS-a.
     */
    private fun recordLegacyProgress(schedule: Schedule) {
        val items = schedule.orderedItems
        val passed = passedItemIds(schedule, schedule.currentCycle)
        val missing = items.take(minOf(schedule.currentPosition, items.size))
            .filter { it.kind == ScheduleItemKind.WORKOUT && it.id !in passed }
        if (missing.isEmpty()) return
        missing.forEach { store.insert(CycleOverride(schedule.id, schedule.currentCycle, it.id, CycleOverrideKind.COMPLETED_WORKOUT)) }
        store.save()
    }

    /** Pozicija iza zadnjeg odrađenog ili preskočenog treninga prije prvog treninga koji je na redu. */
    private fun updatePosition(schedule: Schedule, items: List<ScheduleItem>) {
        val passed = passedItemIds(schedule, schedule.currentCycle)
        var position = 0
        for ((index, item) in items.withIndex()) {
            if (item.id in passed) position = index + 1 else if (isPlayable(item)) break
        }
        schedule.currentPosition = position
    }

    companion object {
        /** Uobičajena gornja granica broja ciklusa u uređivaču. */
        const val USUAL_MAX_CYCLE_COUNT = 52

        /** Dopušteni broj ciklusa: ne manje od tekućeg ciklusa, a gornja granica raste s rasporedom. */
        fun cycleCountRange(currentCycle: Int): IntRange {
            val lower = maxOf(currentCycle, 1)
            return lower..maxOf(USUAL_MAX_CYCLE_COUNT, lower)
        }
    }
}
