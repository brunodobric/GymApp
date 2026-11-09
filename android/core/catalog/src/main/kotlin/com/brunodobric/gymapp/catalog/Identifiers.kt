package com.brunodobric.gymapp.catalog

import java.util.UUID

/**
 * UUID kao tekst velikim slovima, isto kao Swiftov `uuidString`.
 *
 * Ključevi vježbi ("u:<UUID>") i id-jevi u sigurnosnoj kopiji moraju biti isti na iOS-u i Androidu,
 * a Javin `UUID.toString()` daje mala slova.
 */
val UUID.uppercaseString: String get() = toString().uppercase()
