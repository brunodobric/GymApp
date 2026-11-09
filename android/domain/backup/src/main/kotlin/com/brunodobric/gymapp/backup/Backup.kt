package com.brunodobric.gymapp.backup

/** Greške pri uvozu. */
sealed class BackupException(message: String) : Exception(message) {
    /** Datoteka nije sigurnosna kopija ove aplikacije. */
    data object UnsupportedFormat : BackupException("Datoteka nije sigurnosna kopija aplikacije") {
        private fun readResolve(): Any = UnsupportedFormat
    }

    /** Datoteka je iz novije verzije aplikacije. */
    data class NewerVersion(val version: Int) : BackupException("Kopija je iz novije verzije ($version)")

    /** CSV nema očekivana zaglavlja ili je redak neispravan. */
    data class InvalidCsv(val line: Int) : BackupException("Neispravan CSV u retku $line")
}

/** Što je uvoz napravio. Zapisi s `id` koji već postoji se preskaču, pa je uvoz siguran i na već popunjenoj bazi. */
data class BackupImportResult(var added: Int = 0, var skipped: Int = 0)
