package com.thanhhao.esp32_navride

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject

/** Hàng đợi riêng của app; không chứa token và không đưa điểm GPS vào cache Firestore. */
internal class FleetOutbox(context: Context, name: String = "fleet-outbox.db") : SQLiteOpenHelper(context, name, null, 1) {
    data class Entry(val id: Long, val uid: String, val kind: String, val path: String, val fields: JSONObject)

    override fun onConfigure(db: SQLiteDatabase) {
        // Xóa nội dung ô đã nhận ACK và trả lại trang trống, không giữ lịch sử trong freelist.
        db.rawQuery("PRAGMA secure_delete=ON", null).use { it.moveToFirst() }
        db.rawQuery("PRAGMA auto_vacuum=FULL", null).use { it.moveToFirst() }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE pending (id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT NOT NULL, " +
            "kind TEXT NOT NULL, path TEXT NOT NULL, fields TEXT NOT NULL)")
        db.execSQL("CREATE INDEX pending_owner ON pending(uid, id)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun add(uid: String, kind: String, path: String, fields: JSONObject) {
        require(uid.isNotBlank() && kind in setOf("start", "point", "end"))
        val collection = if (kind == "point") "track_points" else "trips"
        require(path.matches(Regex("fleets/[A-Za-z0-9_-]{1,64}/vehicles/[A-Za-z0-9_-]{1,64}/$collection/" +
            "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")))
        writableDatabase.insertOrThrow("pending", null, ContentValues().apply {
            put("uid", uid); put("kind", kind); put("path", path); put("fields", fields.toString())
        })
    }

    fun count(uid: String? = null, pointsOnly: Boolean = false): Int {
        val clauses = mutableListOf<String>()
        val args = mutableListOf<String>()
        if (uid != null) { clauses.add("uid = ?"); args.add(uid) }
        if (pointsOnly) clauses.add("kind = 'point'")
        val where = if (clauses.isEmpty()) "" else " WHERE " + clauses.joinToString(" AND ")
        return readableDatabase.rawQuery("SELECT COUNT(*) FROM pending$where", args.toTypedArray()).use {
            it.moveToFirst(); it.getInt(0)
        }
    }

    private fun first(uid: String): Entry? = readableDatabase.rawQuery(
        "SELECT id, uid, kind, path, fields FROM pending WHERE uid = ? ORDER BY id LIMIT 1", arrayOf(uid),
    ).use {
        if (!it.moveToFirst()) null else Entry(it.getLong(0), it.getString(1), it.getString(2),
            it.getString(3), JSONObject(it.getString(4)))
    }

    /** upload chỉ được trả về bình thường sau ACK server hoặc xác minh bản ghi trùng khớp. */
    fun flush(uid: String, mayContinue: () -> Boolean = { true }, upload: (Entry) -> Unit) {
        // Giới hạn một lượt để nhường thời gian cho Android và các thao tác ghi mới.
        repeat(100) {
            if (!mayContinue()) return
            val entry = first(uid) ?: return
            upload(entry)
            check(writableDatabase.delete("pending", "id = ? AND uid = ?",
                arrayOf(entry.id.toString(), uid)) == 1)
        }
    }
}
