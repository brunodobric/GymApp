package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.units.roundedHalfAwayFromZero
import kotlin.math.abs
import kotlin.math.floor

/**
 * Koje ploče staviti na šipku. Radi u jednoj jedinici (kg ili lbs): cilj, šipka i ploče moraju biti
 * u istoj jedinici, a rezultat je u njoj.
 */
object PlateCalculator {

    data class Result(
        /** Ploče za jednu stranu šipke, od najteže prema najlakšoj. */
        val perSide: List<Double>,
        /** Ukupna težina koja se može postići (šipka + obje strane). */
        val achievedTotal: Double,
        /** Koliko nedostaje do cilja (0 kad je točno). */
        val shortfall: Double,
        val isExact: Boolean,
        /** Cilj je manji od same šipke. */
        val isBelowBar: Boolean,
    )

    /** Najbliža težina koja ne prelazi cilj, uz najmanje ploča. Svaka ploča se može koristiti koliko god puta. */
    fun calculate(target: Double, barbell: Double, plates: List<Double>): Result {
        if (target < barbell - 1e-9) return Result(emptyList(), barbell, 0.0, isExact = false, isBelowBar = true)
        val unit = 100.0 // stotinke jedinice, da decimale poput 1,25 budu cijeli brojevi
        val sizes = plates.filter { it > 0 }.map { (it * unit).roundedHalfAwayFromZero().toInt() }.toSortedSet().reversed()
        val perSideTarget = (floor((target - barbell) / 2 * unit) + 1e-6).toInt()
        if (sizes.isEmpty() || perSideTarget <= 0) {
            val exact = perSideTarget == 0
            return Result(emptyList(), barbell, if (exact) 0.0 else target - barbell, exact, isBelowBar = false)
        }

        // Najmanji broj ploča za svaku težinu do cilja (neograničeni "coin change").
        val fewest = IntArray(perSideTarget + 1) { Int.MAX_VALUE }
        val lastPlate = IntArray(perSideTarget + 1)
        fewest[0] = 0
        for (weight in 1..perSideTarget) {
            for (size in sizes) {
                if (size > weight || fewest[weight - size] == Int.MAX_VALUE) continue
                val count = fewest[weight - size] + 1
                if (count < fewest[weight]) {
                    fewest[weight] = count
                    lastPlate[weight] = size
                }
            }
        }
        var reached = perSideTarget
        while (reached > 0 && fewest[reached] == Int.MAX_VALUE) reached--

        val plateSizes = mutableListOf<Int>()
        var remaining = reached
        while (remaining > 0) {
            plateSizes += lastPlate[remaining]
            remaining -= lastPlate[remaining]
        }
        val perSide = plateSizes.sortedDescending().map { it / unit }
        val achieved = barbell + perSide.sum() * 2
        val shortfall = maxOf(0.0, target - achieved)
        return Result(perSide, achieved, if (shortfall < 1e-6) 0.0 else shortfall, shortfall < 1e-6, isBelowBar = false)
    }

    data class PlateCount(val plate: Double, val count: Int)

    /** Ploče jedne strane grupirane po veličini, od najteže: [20, 20, 5] daje 2×20 i 1×5. */
    fun grouped(perSide: List<Double>): List<PlateCount> {
        val result = mutableListOf<PlateCount>()
        for (plate in perSide) {
            val last = result.lastOrNull()
            if (last != null && last.plate == plate) result[result.size - 1] = last.copy(count = last.count + 1) else result += PlateCount(plate, 1)
        }
        return result
    }

    /** Dostupne ploče nakon što se jedna uključi ili isključi: bez duplikata, od najlakše prema najtežoj. */
    fun setting(plate: Double, enabled: Boolean, plates: List<Double>): List<Double> {
        val result = plates.filter { abs(it - plate) > 1e-9 }.toMutableList()
        if (enabled) result += plate
        return result.sorted()
    }

    /** Uobičajene ploče i šipka za funte (postavke ploča čuvaju se u kilogramima). */
    val DEFAULT_POUND_PLATES = listOf(2.5, 5.0, 10.0, 25.0, 35.0, 45.0)
    const val DEFAULT_POUND_BARBELL = 45.0
}
