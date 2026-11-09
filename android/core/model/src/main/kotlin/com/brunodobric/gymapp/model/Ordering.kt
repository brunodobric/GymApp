package com.brunodobric.gymapp.model

/**
 * Premješta elemente kao `onMove` u SwiftUI-ju: [destination] je indeks prije premještanja.
 * Nepostojeći indeksi se preskaču.
 */
fun <T> MutableList<T>.moveElements(source: Collection<Int>, destination: Int) {
    val valid = source.filter { it in indices }.distinct().sorted()
    val moving = valid.map { this[it] }
    val target = destination - valid.count { it < destination }
    valid.sortedDescending().forEach { removeAt(it) }
    addAll(target.coerceIn(0, size), moving)
}
