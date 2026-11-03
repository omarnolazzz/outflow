package com.outflow.outflow

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.json.JSONObject

/** ¿El texto parece hablar de dinero? Un importe con moneda, nada más. */
object CaptureFilter {
    private val amountRegex = Regex(
        """(S/\.?|PEN|US\$|USD|\$|€|EUR)\s?\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{1,2})?|\d{1,3}(?:[.,]\d{3})*[.,]\d{2}\s?(PEN|USD|EUR|soles)""",
        RegexOption.IGNORE_CASE,
    )

    fun looksLikeMoney(text: String): Boolean = amountRegex.containsMatchIn(text)
}

/** Ventana de claves recientes: la misma notificación re-publicada no se guarda dos veces. */
class RecentKeys(private val capacity: Int = 200) {
    private val seen = LinkedHashSet<String>()

    @Synchronized
    fun firstTime(key: String, text: String): Boolean {
        val id = "$key|${text.hashCode()}"
        if (!seen.add(id)) return false
        if (seen.size > capacity) seen.remove(seen.first())
        return true
    }
}

/**
 * Bandeja de captura (la lee Dart al abrir la app) y preferencias de qué apps se leen.
 * La bandeja es `capture_inbox.jsonl` en `app_flutter`, que es donde
 * `getApplicationDocumentsDirectory()` apunta en Android.
 */
object CaptureStore {
    private const val PREFS = "outflow_capture"
    private const val SEEN = "seen"
    private const val ENABLED = "enabled"
    private val lock = Any()

    /** Apps cuyas notificaciones se leen de entrada → nombre. */
    val SOURCES = mapOf(
        "com.google.android.apps.walletnfcrel" to "Google Wallet",
        "com.google.android.apps.nbu.paisa.user" to "Google Pay",
        "com.bcp.bank.bcp" to "BCP",
        "com.bcp.innovacxion.yapeapp" to "Yape",
        "pe.com.interbank.mobilebanking" to "Interbank",
        "com.bbva.nxt_peru" to "BBVA",
        "pe.com.scotiabank.blpm.android.client" to "Scotiabank",
    )

    fun inboxFile(context: Context) = File(context.getDir("flutter", Context.MODE_PRIVATE), "capture_inbox.jsonl")

    fun isoNow(millis: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date(millis))

    fun eventJson(sourceKey: String, sourceLabel: String, text: String, receivedAt: String): String =
        JSONObject()
            .put("sourceKey", sourceKey)
            .put("sourceLabel", sourceLabel)
            .put("text", text)
            .put("receivedAt", receivedAt)
            .toString()

    fun append(context: Context, sourceKey: String, sourceLabel: String, text: String, receivedAtMillis: Long) =
        appendLine(inboxFile(context), eventJson(sourceKey, sourceLabel, text, isoNow(receivedAtMillis)))

    /** Abre, añade una línea completa y cierra: si Dart renombra el archivo no se pierde nada. */
    fun appendLine(file: File, json: String) {
        synchronized(lock) {
            file.parentFile?.mkdirs()
            // Si un fallo dejó una línea sin cerrar, la nueva empieza en renglón aparte.
            val needsBreak = file.exists() && file.length() > 0 && RandomAccessFile(file, "r").use {
                it.seek(it.length() - 1)
                it.read() != '\n'.code
            }
            FileOutputStream(file, true).use { out ->
                val line = (if (needsBreak) "\n" else "") + json + "\n"
                out.write(line.toByteArray(Charsets.UTF_8))
                out.flush()
                out.fd.sync()
            }
        }
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun readMap(context: Context, key: String): JSONObject =
        try { JSONObject(prefs(context).getString(key, null) ?: "{}") } catch (_: Exception) { JSONObject() }

    /** Solo paquete y nombre; nunca el texto. */
    fun noteSeen(context: Context, packageName: String, label: String) {
        synchronized(lock) {
            val seen = readMap(context, SEEN)
            if (seen.optString(packageName) == label) return
            seen.put(packageName, label)
            prefs(context).edit().putString(SEEN, seen.toString()).apply()
        }
    }

    /** Apps conocidas más las vistas, como (paquete, nombre). */
    fun seenApps(context: Context): List<Pair<String, String>> {
        val seen = readMap(context, SEEN)
        val all = LinkedHashMap<String, String>(SOURCES)
        seen.keys().forEach { if (it !in all) all[it] = seen.optString(it, it) }
        return all.toList()
    }

    fun isEnabled(context: Context, packageName: String): Boolean {
        val overrides = readMap(context, ENABLED)
        return if (overrides.has(packageName)) overrides.optBoolean(packageName) else packageName in SOURCES
    }

    fun enabledApps(context: Context): List<String> = seenApps(context).map { it.first }.filter { isEnabled(context, it) }

    fun setEnabled(context: Context, packageName: String, enabled: Boolean) {
        synchronized(lock) {
            val overrides = readMap(context, ENABLED).put(packageName, enabled)
            prefs(context).edit().putString(ENABLED, overrides.toString()).apply()
        }
    }
}
