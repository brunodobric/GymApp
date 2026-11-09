package com.brunodobric.gymapp.model

import com.brunodobric.gymapp.catalog.uppercaseString
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.time.Instant
import java.util.UUID

/** UUID kao tekst velikim slovima (kao na iOS-u). */
object UUIDSerializer : KSerializer<UUID> {
    override val descriptor = PrimitiveSerialDescriptor("UUID", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: UUID) = encoder.encodeString(value.uppercaseString)
    override fun deserialize(decoder: Decoder): UUID = UUID.fromString(decoder.decodeString())
}

/** Trenutak kao milisekunde od 1970. Samo za lokalno spremanje, ne za kopiju (ona ima svoj format). */
object InstantSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("Instant", PrimitiveKind.LONG)
    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeLong(value.toEpochMilli())
    override fun deserialize(decoder: Decoder): Instant = Instant.ofEpochMilli(decoder.decodeLong())
}

/** JSON za zapise u lokalnoj bazi: nepoznata polja (novija verzija) se preskaču, zadane vrijednosti se pišu. */
val RecordJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
}
