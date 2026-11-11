package com.brunodobric.gymapp.backup

import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

/** Najmanji CSV (RFC 4180): polja sa zarezom, navodnicima ili novim retkom stavljaju se u navodnike. */
object Csv {
    fun line(fields: List<String>): String = fields.joinToString(",", transform = ::escape)

    fun escape(field: String): String {
        if (field.none { it == ',' || it == '"' || it == '\n' || it == '\r' }) return field
        return "\"" + field.replace("\"", "\"\"") + "\""
    }

    /**
     * Čita cijeli tekst u retke polja. Prazni završni redak se ignorira. [separator] je zarez za vlastiti CSV,
     * a točka-zarez za izvoze nekih drugih aplikacija. CRLF je jedan kraj retka (kao `Character` u Swiftu).
     */
    fun parse(text: String, separator: Char = ','): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val field = StringBuilder()
        var inQuotes = false
        var hasContent = false

        fun endRow() {
            row += field.toString()
            field.setLength(0)
            if (hasContent || row.size > 1 || row[0].isNotEmpty()) rows += row
            row = mutableListOf()
            hasContent = false
        }

        var index = 0
        while (index < text.length) {
            val character = text[index]
            index += 1
            if (inQuotes) {
                if (character == '"') {
                    if (index < text.length && text[index] == '"') {
                        field.append('"')
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            when (character) {
                '"' -> {
                    inQuotes = true
                    hasContent = true
                }
                separator -> {
                    row += field.toString()
                    field.setLength(0)
                    hasContent = true
                }
                '\r' -> {
                    if (index < text.length && text[index] == '\n') index += 1
                    endRow()
                }
                '\n' -> endRow()
                else -> field.append(character)
            }
        }
        if (hasContent || field.isNotEmpty() || row.isNotEmpty()) endRow()
        return rows
    }
}

/** Tekst uvezene datoteke iz bajtova. */
object ImportText {
    /**
     * UTF-8, ili UTF-16 kad datoteka počinje njegovim BOM-om (neke aplikacije i Excel tako izvoze CSV).
     * BOM se uklanja, da prvi naziv stupca ostane ispravan.
     */
    fun decode(bytes: ByteArray): String {
        fun starts(vararg prefix: Int) = bytes.size >= prefix.size && prefix.indices.all { (bytes[it].toInt() and 0xFF) == prefix[it] }
        val charset = when {
            starts(0xFF, 0xFE) -> Charsets.UTF_16LE
            starts(0xFE, 0xFF) -> Charsets.UTF_16BE
            else -> Charsets.UTF_8
        }
        return String(bytes, charset).removePrefix("\uFEFF")
    }
}

/** Datumi u CSV-u: ISO 8601 s milisekundama (UTC), pa su čitljivi i vraćaju se bez gubitka u milisekundi. */
object CsvDate {
    private val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSX").withZone(ZoneOffset.UTC)

    fun string(date: Instant?): String = date?.let { formatter.format(it) } ?: ""

    fun parse(text: String): Instant? {
        if (text.isEmpty()) return null
        return try {
            Instant.from(formatter.parse(text))
        } catch (_: DateTimeParseException) {
            null
        }
    }
}
