package com.brunodobric.gymapp.stats

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Naredba SVG putanje. MuscleMap koristi samo apsolutne naredbe M, L, C i Z. */
sealed interface PathCommand {
    data class Move(val x: Double, val y: Double) : PathCommand
    data class Line(val x: Double, val y: Double) : PathCommand
    data class Curve(val c1x: Double, val c1y: Double, val c2x: Double, val c2y: Double, val x: Double, val y: Double) : PathCommand
    data object Close : PathCommand
}

/**
 * Čita SVG podatke putanje (`d`) u naredbe. Podržane su apsolutne M, L, C i Z, s ponavljanjem argumenata
 * (npr. "C a b c d e f g h i j k l"). Nepoznata naredba ili nepotpuni argumenti prekidaju čitanje te putanje.
 */
object SVGPathParser {
    private sealed interface Token {
        data class Command(val letter: Char) : Token
        data class Number(val value: Double) : Token
    }

    fun parse(data: String): List<PathCommand> {
        val tokens = tokenize(data)
        val commands = mutableListOf<PathCommand>()
        var index = 0
        var current: Char? = null

        fun numbers(count: Int): List<Double>? {
            val result = mutableListOf<Double>()
            var cursor = index
            while (result.size < count && cursor < tokens.size) {
                val token = tokens[cursor] as? Token.Number ?: break
                result += token.value
                cursor++
            }
            if (result.size != count) return null
            index = cursor
            return result
        }

        while (index < tokens.size) {
            val token = tokens[index]
            if (token is Token.Command) {
                current = token.letter
                index++
                if (token.letter == 'Z' || token.letter == 'z') {
                    commands += PathCommand.Close
                    continue
                }
            }
            when (current ?: return commands) {
                'M' -> {
                    val v = numbers(2) ?: return commands
                    commands += PathCommand.Move(v[0], v[1])
                    current = 'L' // dodatni parovi iza M su linije
                }
                'L' -> {
                    val v = numbers(2) ?: return commands
                    commands += PathCommand.Line(v[0], v[1])
                }
                'C' -> {
                    val v = numbers(6) ?: return commands
                    commands += PathCommand.Curve(v[0], v[1], v[2], v[3], v[4], v[5])
                }
                else -> return commands
            }
        }
        return commands
    }

    private fun tokenize(data: String): List<Token> {
        val tokens = mutableListOf<Token>()
        val number = StringBuilder()
        var hasDot = false

        fun flush() {
            if (number.isNotEmpty()) number.toString().toDoubleOrNull()?.let { tokens += Token.Number(it) }
            number.clear()
            hasDot = false
        }

        for (character in data) {
            when (character) {
                in '0'..'9' -> number.append(character)
                '.' -> {
                    if (hasDot) flush()
                    hasDot = true
                    number.append(character)
                }
                '-' -> {
                    flush()
                    number.append(character)
                }
                ' ', ',', '\n', '\t' -> flush()
                else -> {
                    flush()
                    tokens += Token.Command(character)
                }
            }
        }
        flush()
        return tokens
    }
}

/** Jedan crtež iz MuscleMap resursa (obris tijela ili jedna mišićna ploha). */
@Serializable
data class BodyMapShape(
    val id: String,
    /** Grupa mišića u MuscleMap nazivlju (npr. "QUADS"). Obris tijela je nema. */
    val group: String? = null,
    @SerialName("d") val pathData: String,
)

/** Tijelo jednog spola i strane (sprijeda ili straga) s obrisom i mišićnim plohama. */
@Serializable
data class BodyMapDiagram(
    val viewBox: List<Double>,
    /** Vidljivi dio crteža (x, y, širina, visina). Prednja i stražnja strana istog spola imaju isti okvir. */
    val bounds: List<Double>,
    val outline: List<BodyMapShape>,
    val muscles: List<BodyMapShape>,
)

object BodyMap {
    private val json = Json { ignoreUnknownKeys = true }

    fun key(female: Boolean, back: Boolean): String = "${if (female) "female" else "male"}-${if (back) "back" else "front"}"

    fun decode(data: String): Map<String, BodyMapDiagram> = json.decodeFromString(data)
}
