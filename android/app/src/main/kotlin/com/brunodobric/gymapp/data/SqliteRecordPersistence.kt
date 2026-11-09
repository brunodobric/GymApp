package com.brunodobric.gymapp.data

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.brunodobric.gymapp.model.RecordPersistence
import com.brunodobric.gymapp.model.StoredRecord

/**
 * Korisnička baza na uređaju: jedna SQLite tablica `records(type, id, json)` (docs/android.md, odjeljak 0).
 * `GymStore` drži graf u memoriji i ovdje zapisuje samo promijenjene i obrisane zapise, u jednoj transakciji.
 *
 * Bez WAL-a, da je cijela baza u jednoj datoteci: sustavska sigurnosna kopija (Auto Backup) kopira samo nju.
 */
class SqliteRecordPersistence(context: Context) : RecordPersistence {

    private val helper = object : SQLiteOpenHelper(context.applicationContext, DATABASE_NAME, null, VERSION) {
        override fun onConfigure(db: SQLiteDatabase) {
            db.disableWriteAheadLogging()
        }

        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL(
                "CREATE TABLE $TABLE (type TEXT NOT NULL, id TEXT NOT NULL, json TEXT NOT NULL, PRIMARY KEY (type, id))",
            )
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
    }

    override fun loadAll(): List<StoredRecord> {
        val result = mutableListOf<StoredRecord>()
        helper.readableDatabase.query(TABLE, arrayOf("type", "id", "json"), null, null, null, null, null).use { cursor ->
            while (cursor.moveToNext()) {
                result += StoredRecord(cursor.getString(0), cursor.getString(1), cursor.getString(2))
            }
        }
        return result
    }

    override fun write(upserts: List<StoredRecord>, deletes: List<Pair<String, String>>) {
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            for ((type, id) in deletes) {
                db.delete(TABLE, "type = ? AND id = ?", arrayOf(type, id))
            }
            for (record in upserts) {
                val values = ContentValues(3).apply {
                    put("type", record.type)
                    put("id", record.id)
                    put("json", record.json)
                }
                db.insertWithOnConflict(TABLE, null, values, SQLiteDatabase.CONFLICT_REPLACE)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    companion object {
        /** Isto ime je u pravilima sigurnosne kopije (`res/xml/data_extraction_rules.xml`). */
        const val DATABASE_NAME = "gym.db"
        private const val VERSION = 1
        private const val TABLE = "records"
    }
}
