package com.example.smsgo

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class RepliesDbHelper(context: Context) : SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {
  companion object {
    private const val DB_NAME = "smsgo_native.db"
    private const val DB_VERSION = 1
    private const val TABLE = "replies"
  }

  override fun onCreate(db: SQLiteDatabase) {
    db.execSQL("""
      CREATE TABLE IF NOT EXISTS $TABLE(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lead_id INTEGER,
        phone_number TEXT NOT NULL,
        message TEXT NOT NULL,
        received_at TEXT NOT NULL
      )
    """.trimIndent())
  }

  override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
    // no-op for now
  }

  fun insertReply(phoneNumber: String, message: String, receivedAt: String): Long {
    val db = writableDatabase
    val cv = ContentValues().apply {
      put("phone_number", phoneNumber)
      put("message", message)
      put("received_at", receivedAt)
    }
    return db.insert(TABLE, null, cv)
  }

  fun getAllReplies(): List<Map<String, Any?>> {
    val db = readableDatabase
    val rows = mutableListOf<Map<String, Any?>>()
    val cursor: Cursor = db.query(TABLE, null, null, null, null, null, "id ASC")
    cursor.use {
      while (it.moveToNext()) {
        val id = it.getLong(it.getColumnIndexOrThrow("id"))
        val leadId = if (!it.isNull(it.getColumnIndexOrThrow("lead_id"))) it.getLong(it.getColumnIndexOrThrow("lead_id")) else null
        val phone = it.getString(it.getColumnIndexOrThrow("phone_number"))
        val msg = it.getString(it.getColumnIndexOrThrow("message"))
        val receivedAt = it.getString(it.getColumnIndexOrThrow("received_at"))
        rows.add(mapOf("id" to id, "lead_id" to leadId, "phone_number" to phone, "message" to msg, "received_at" to receivedAt))
      }
    }
    return rows
  }

  fun deleteReply(id: Long): Int {
    val db = writableDatabase
    return db.delete(TABLE, "id = ?", arrayOf(id.toString()))
  }
}
