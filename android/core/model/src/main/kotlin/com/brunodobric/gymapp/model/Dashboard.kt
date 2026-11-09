package com.brunodobric.gymapp.model

/**
 * Vrste kartica koje korisnik može dodati na Početnu. Nepoznate vrste (iz novije verzije aplikacije)
 * ostaju u bazi, ali se ne prikazuju.
 */
enum class DashboardCardKind(val raw: String) {
    THIS_WEEK("thisWeek"),

    /** Tekući mjesec, kao Ovaj tjedan, s prosjekom treninga tjedno. */
    THIS_MONTH("thisMonth"),

    /** Tekuća godina s treninzima po mjesecima. */
    THIS_YEAR("thisYear"),
    LAST_WORKOUT("lastWorkout"),
    BODY_WEIGHT("bodyWeight"),
    PLATE_CALCULATOR("plateCalculator"),
    ;

    /** Mala kartica: dvije uzastopne male kartice stoje jedna do druge ([DashboardLayout.rows]). */
    val isCompact: Boolean get() = this == BODY_WEIGHT || this == PLATE_CALCULATOR

    companion object {
        fun fromRaw(raw: String): DashboardCardKind? = entries.firstOrNull { it.raw == raw }

        /** Vrste koje Početna dobiva na praznom početku, ovim redom. */
        val defaults = listOf(THIS_WEEK, LAST_WORKOUT)

        /** Ukinute vrste (tjedni volumen i sljedeći trening). */
        internal const val RETIRED_WEEKLY_VOLUME = "weeklyVolume"
        internal const val RETIRED_NEXT_WORKOUT = "nextWorkout"
    }
}

val DashboardCard.kind: DashboardCardKind? get() = DashboardCardKind.fromRaw(kindRaw)

/** Slaganje kartica na Početnoj: dodavanje, uklanjanje i premještanje. Redoslijed je u `orderIndex`. */
class DashboardLayout(private val store: GymStore) {

    /** Sve kartice po redoslijedu (i one nepoznate vrste). */
    fun allCards(): List<DashboardCard> = store.dashboardCards.sortedBy { it.orderIndex }

    /** Kartice koje se prikazuju: poznate vrste, najviše jedna po vrsti. */
    fun cards(): List<DashboardCard> = visible(allCards())

    /** Vrste koje još nisu na Početnoj. */
    fun availableKinds(): List<DashboardCardKind> {
        val present = cards().mapNotNull { it.kind }.toSet()
        return DashboardCardKind.entries.filter { it !in present }
    }

    /** Dodaje karticu na kraj. Ako ta vrsta već postoji, ne radi ništa. */
    fun add(kind: DashboardCardKind): DashboardCard? {
        if (kind !in availableKinds()) return null
        val next = (allCards().lastOrNull()?.orderIndex ?: -1) + 1
        val card = store.insert(DashboardCard(kind.raw, next))
        store.save()
        return card
    }

    /**
     * Početna bez ijedne kartice dobiva zadane kartice. Samo na praznoj Početnoj: ako kartice već postoje,
     * korisnik ih je složio sam, pa se kartica koju je uklonio ne vraća.
     */
    fun seedDefaults(): List<DashboardCard> {
        if (allCards().isNotEmpty()) return emptyList()
        val cards = DashboardCardKind.defaults.mapIndexed { index, kind -> store.insert(DashboardCard(kind.raw, index)) }
        store.save()
        return cards
    }

    /**
     * Prijelaz na kartice nove Početne: kartica tjednog volumena postaje Ovaj tjedan na istom mjestu,
     * kartica sljedećeg treninga se uklanja, a Početna bez kartice Ovaj tjedan dobiva je na vrhu.
     * Na Androidu nema starih podataka, ali uvoz sigurnosne kopije s iOS-a ih može donijeti.
     */
    fun upgradeToWeekCard() {
        val all = allCards()
        if (all.isEmpty()) return
        val week = DashboardCardKind.THIS_WEEK.raw
        var hasWeek = all.any { it.kindRaw == week }
        val cards = mutableListOf<DashboardCard>()
        for (card in all) {
            when {
                card.kindRaw == DashboardCardKind.RETIRED_WEEKLY_VOLUME && !hasWeek -> {
                    card.kindRaw = week
                    hasWeek = true
                    cards += card
                }
                card.kindRaw == DashboardCardKind.RETIRED_WEEKLY_VOLUME ||
                    card.kindRaw == DashboardCardKind.RETIRED_NEXT_WORKOUT -> store.delete(card)
                else -> cards += card
            }
        }
        if (!hasWeek) cards.add(0, store.insert(DashboardCard(week, 0)))
        renumber(cards)
        store.save()
    }

    fun remove(card: DashboardCard) {
        store.delete(card)
        renumber(allCards())
        store.save()
    }

    /** Premješta prikazane kartice (indeksi su u [cards]). */
    fun move(fromIndices: Collection<Int>, toIndex: Int) {
        val visible = cards().toMutableList()
        visible.moveElements(fromIndices, toIndex)
        val hidden = allCards().filter { card -> visible.none { it === card } }
        renumber(visible + hidden)
        store.save()
    }

    private fun renumber(cards: List<DashboardCard>) {
        cards.forEachIndexed { index, card -> if (card.orderIndex != index) card.orderIndex = index }
    }

    companion object {
        /** Kao [cards], za kartice koje je ekran već dohvatio (po `orderIndex`). */
        fun visible(all: List<DashboardCard>): List<DashboardCard> {
            val seen = mutableSetOf<DashboardCardKind>()
            return all.filter { card -> card.kind?.let(seen::add) ?: false }
        }

        /** Redovi Početne: velika kartica je sama u redu, a dvije uzastopne male kartice dijele red. */
        fun rows(kinds: List<DashboardCardKind>): List<List<DashboardCardKind>> {
            val rows = mutableListOf<MutableList<DashboardCardKind>>()
            for (kind in kinds) {
                val last = rows.lastOrNull()
                if (kind.isCompact && last != null && last.size == 1 && last[0].isCompact) last += kind else rows += mutableListOf(kind)
            }
            return rows
        }
    }
}
