package com.brunodobric.gymapp.catalog

import java.text.Collator
import java.text.Normalizer
import java.util.Locale
import java.util.UUID

/** Sažetak vježbe za popis i pretragu: isti oblik za službene i vlastite vježbe. */
class ExerciseSummary(
    val source: Source,
    val name: String,
    /** Nazivi na drugim jezicima: pretraga pronalazi vježbu i po engleskom i po hrvatskom nazivu. */
    alternativeNames: List<String> = emptyList(),
    val category: ExerciseCategory?,
    /** Vrsta se računa iz kategorije kad je izvor ne zna (vlastite vježbe). */
    kind: ExerciseKind? = null,
    val muscles: List<Muscle>,
    val equipment: Equipment?,
    val isArchived: Boolean,
) {
    sealed interface Source {
        data class Catalog(val id: String) : Source
        data class Custom(val id: UUID) : Source
    }

    val kind: ExerciseKind = kind ?: ExerciseKind.fallback(category)

    internal val searchText: String = ExerciseSearch.normalize((listOf(name) + alternativeNames).joinToString(" "))

    val id: String
        get() = when (source) {
            is Source.Catalog -> "c:${source.id}"
            is Source.Custom -> "u:${source.id.uppercaseString}"
        }

    val isCustom: Boolean get() = source is Source.Custom

    override fun equals(other: Any?): Boolean =
        other is ExerciseSummary && other.source == source && other.name == name && other.category == category &&
            other.kind == kind && other.muscles == muscles && other.equipment == equipment &&
            other.isArchived == isArchived && other.searchText == searchText

    override fun hashCode(): Int = listOf(source, name, category, kind, muscles, equipment, isArchived).hashCode()

    override fun toString(): String = "ExerciseSummary($id, $name)"
}

data class ExerciseFilter(
    val query: String = "",
    /** Vrsta vježbe (stranica vrste na početnoj kataloga). Nije dio [isActive]: postavlja je ekran, a ne list s filterima. */
    val kinds: Set<ExerciseKind> = emptySet(),
    val categories: Set<ExerciseCategory> = emptySet(),
    val muscles: Set<Muscle> = emptySet(),
    val equipment: Set<Equipment> = emptySet(),
    val origin: Origin = Origin.ALL,
    val includeArchived: Boolean = false,
) {
    enum class Origin { ALL, OFFICIAL, CUSTOM }

    val isActive: Boolean
        get() = categories.isNotEmpty() || muscles.isNotEmpty() || equipment.isNotEmpty() || origin != Origin.ALL

    /** Razlikuje li se filter od početnog filtera popisa ([base]), ne gledajući upit. */
    fun differs(base: ExerciseFilter): Boolean = copy(query = base.query) != base

    /** Vraća početni filter popisa, a zadržava upit. */
    fun reset(base: ExerciseFilter): ExerciseFilter = base.copy(query = query)
}

/**
 * Nazivi kategorija, mišića i opreme kako ih korisnik vidi. Pretraga ih uspoređuje s upitom,
 * pa "sprava" pronalazi sve vježbe na spravi, a "triceps" sve vježbe za triceps.
 */
class ExerciseSearchLabels(
    category: (ExerciseCategory) -> String,
    muscle: (Muscle) -> String,
    equipment: (Equipment) -> String,
) {
    private val categories = ExerciseCategory.entries.associateWith { ExerciseSearch.normalize(category(it)) }
    private val muscles = Muscle.entries.associateWith { ExerciseSearch.normalize(muscle(it)) }
    private val equipmentTitles = Equipment.entries.associateWith { ExerciseSearch.normalize(equipment(it)) }

    /** Svi nazivi vježbe u jednom tekstu, odvojeni razmakom. */
    internal fun text(item: ExerciseSummary): String {
        val parts = mutableListOf<String>()
        item.category?.let { categories[it] }?.let(parts::add)
        parts += item.muscles.mapNotNull { muscles[it] }
        item.equipment?.let { equipmentTitles[it] }?.let(parts::add)
        return parts.filter { it.isNotEmpty() }.joinToString(" ")
    }

    companion object {
        /** Bez naziva: pretraga samo po nazivu vježbe. */
        val NONE = ExerciseSearchLabels({ "" }, { "" }, { "" })
    }
}

object ExerciseSearch {
    private val combiningMarks = Regex("\\p{M}+")

    /** Mala slova, bez dijakritika i s đ → d, pa "cucanj" pronalazi "Čučanj", a "dizanje" "Dizanje". */
    fun normalize(text: String): String {
        val replaced = text.replace("đ", "d").replace("Đ", "d")
        // NFKD rastavlja slova s dijakriticima i izjednačava širinu znakova (kao widthInsensitive na iOS-u).
        val decomposed = Normalizer.normalize(replaced, Normalizer.Form.NFKD)
        return combiningMarks.replace(decomposed, "").lowercase(Locale.ROOT)
    }

    /** Broj vježbi po vrsti, bez arhiviranih (kartice na početnoj kataloga). */
    fun countsByKind(items: List<ExerciseSummary>): Map<ExerciseKind, Int> =
        items.filter { !it.isArchived }.groupingBy { it.kind }.eachCount()

    /**
     * Filtrira i poredava: najprije nazivi koji počinju upitom, zatim riječi koje počinju upitom, pa ostalo,
     * a na kraju vježbe koje upitu odgovaraju tek po kategoriji, mišiću ili opremi.
     * Svaka riječ upita mora se pojaviti u nazivu ili u [labels]. Bez upita rezultat je abecedni.
     */
    fun apply(
        filter: ExerciseFilter,
        items: List<ExerciseSummary>,
        labels: ExerciseSearchLabels = ExerciseSearchLabels.NONE,
        locale: Locale = Locale.getDefault(),
    ): List<ExerciseSummary> {
        val tokens = normalize(filter.query).split(Regex("\\s+")).filter { it.isNotEmpty() }
        val scored = mutableListOf<Pair<ExerciseSummary, Int>>()
        for (item in items) {
            if (item.isArchived && !filter.includeArchived) continue
            when (filter.origin) {
                ExerciseFilter.Origin.ALL -> Unit
                ExerciseFilter.Origin.OFFICIAL -> if (item.isCustom) continue
                ExerciseFilter.Origin.CUSTOM -> if (!item.isCustom) continue
            }
            if (filter.kinds.isNotEmpty() && item.kind !in filter.kinds) continue
            if (filter.categories.isNotEmpty() && (item.category == null || item.category !in filter.categories)) continue
            if (filter.muscles.isNotEmpty() && item.muscles.none { it in filter.muscles }) continue
            if (filter.equipment.isNotEmpty() && (item.equipment == null || item.equipment !in filter.equipment)) continue
            val score = relevance(tokens, item.searchText, if (tokens.isEmpty()) "" else labels.text(item)) ?: continue
            scored += item to score
        }
        val names = NaturalOrder(locale)
        return scored
            .sortedWith(compareBy<Pair<ExerciseSummary, Int>> { it.second }.thenComparator { a, b -> names.compare(a.first.name, b.first.name) })
            .map { it.first }
    }

    /**
     * Rezultati pretrage s odabranim vježbama izdvojenima na vrh, da korisnik tijekom pretrage vidi što je odabrao.
     * [selected] su id-evi redom odabira. Odabrane se traže u [all], pa se vide i kad ne odgovaraju upitu,
     * a iz [results] se izbacuju da se ne ponavljaju. Nepoznati id-evi se preskaču.
     */
    fun pinningSelected(
        selected: List<String>,
        results: List<ExerciseSummary>,
        all: List<ExerciseSummary>,
    ): Pair<List<ExerciseSummary>, List<ExerciseSummary>> {
        if (selected.isEmpty()) return emptyList<ExerciseSummary>() to results
        val byId = LinkedHashMap<String, ExerciseSummary>()
        all.forEach { byId.putIfAbsent(it.id, it) }
        val pinned = selected.mapNotNull { byId[it] }
        val pinnedIds = pinned.map { it.id }.toSet()
        return pinned to results.filter { it.id !in pinnedIds }
    }

    /** null ako neka riječ ne postoji ni u nazivu ni u [labels]. Manje je bolje. */
    private fun relevance(tokens: List<String>, text: String, labels: String): Int? {
        if (tokens.isEmpty()) return 0
        var worst = 0
        tokens.forEachIndexed { position, token ->
            val index = text.indexOf(token)
            val score = when {
                index >= 0 -> {
                    val atStart = index == 0
                    val atWordStart = atStart || text[index - 1] == ' '
                    if (atStart && position == 0) 0 else if (atWordStart) 1 else 2
                }
                labels.contains(token) -> 3
                else -> return null
            }
            worst = maxOf(worst, score)
        }
        return worst
    }
}

/**
 * Poredak naziva kao Finder i Swiftov `localizedStandardCompare`: bez obzira na velika slova,
 * prema pravilima jezika, a brojevi po vrijednosti ("Vježba 2" prije "Vježba 10").
 */
class NaturalOrder(locale: Locale = Locale.getDefault()) : Comparator<String> {
    private val collator = Collator.getInstance(locale).apply { strength = Collator.SECONDARY }
    private val chunk = Regex("\\d+|\\D+")

    override fun compare(a: String, b: String): Int {
        val left = chunk.findAll(a).map { it.value }.toList()
        val right = chunk.findAll(b).map { it.value }.toList()
        for (i in 0 until minOf(left.size, right.size)) {
            val x = left[i]
            val y = right[i]
            val result = if (x[0].isDigit() && y[0].isDigit()) {
                x.trimStart('0').length.compareTo(y.trimStart('0').length).takeIf { it != 0 }
                    ?: x.trimStart('0').compareTo(y.trimStart('0'))
            } else {
                collator.compare(x, y)
            }
            if (result != 0) return result
        }
        return left.size.compareTo(right.size)
    }
}
