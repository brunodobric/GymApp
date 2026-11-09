package com.brunodobric.gymapp.catalog

/** Tekst licence za prikaz na ekranu O aplikaciji. */
object LicenseText {
    /**
     * Tvrdi prijelomi unutar odlomaka se spajaju da tekst teče po širini ekrana. Prazni redovi
     * i stavke koje počinju s "- " ostaju zasebni odlomci.
     */
    fun reflowed(raw: String): String {
        val paragraphs = mutableListOf<String>()
        var current = ""
        for (line in raw.split("\n")) {
            val text = line.trim(' ', '\t')
            if (text.isEmpty() || text.startsWith("- ")) {
                if (current.isNotEmpty()) paragraphs += current
                current = text
            } else {
                current += if (current.isEmpty()) text else " $text"
            }
        }
        if (current.isNotEmpty()) paragraphs += current
        return paragraphs.joinToString("\n\n")
    }
}
