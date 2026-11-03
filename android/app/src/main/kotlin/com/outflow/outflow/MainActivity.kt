package com.outflow.outflow

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.abs

// local_auth necesita una FragmentActivity para mostrar el diálogo biométrico.
class MainActivity : FlutterFragmentActivity() {
    private var shareChannel: MethodChannel? = null
    private var pendingShare: String? = null
    private var pendingShareFailed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Lectura de tickets en el teléfono con ML Kit (la foto no sale de él).
        MethodChannel(messenger, "outflow/ocr").setMethodCallHandler { call, result ->
            if (call.method != "recognizeText") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path == null) {
                result.error("image", "No se pudo abrir la foto.", null)
                return@setMethodCallHandler
            }
            try {
                val image = InputImage.fromFilePath(this, Uri.fromFile(File(path)))
                TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                    .process(image)
                    .addOnSuccessListener { text -> result.success(lines(text).joinToString("\n")) }
                    .addOnFailureListener { e -> result.error("mlkit", e.message, null) }
            } catch (e: Exception) {
                result.error("image", e.message, null)
            }
        }

        // Captura automática: permiso de notificaciones y apps que se leen.
        MethodChannel(messenger, "outflow/payments").setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(listenerEnabled())
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "seenApps" -> result.success(
                    CaptureStore.seenApps(this).map { (pkg, label) -> mapOf("package" to pkg, "label" to label) },
                )
                "enabledApps" -> result.success(CaptureStore.enabledApps(this))
                "setEnabled" -> {
                    val pkg = call.argument<String>("package")
                    val on = call.argument<Boolean>("enabled")
                    if (pkg == null || on == null) {
                        result.error("args", "Faltan datos.", null)
                    } else {
                        CaptureStore.setEnabled(this, pkg, on)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Compartir una captura con Outflow: la imagen se copia a la caché y la app la
        // lee y la borra. Con la app cerrada espera a que Dart la pida (initialImage).
        shareChannel = MethodChannel(messenger, "outflow/share").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "initialImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val failed = pendingShareFailed
                val path = pendingShare
                pendingShare = null
                pendingShareFailed = false
                if (failed) result.error("copy", "No se pudo abrir la imagen compartida.", null) else result.success(path)
            }
        }
        readShare(intent)?.let { share ->
            pendingShare = share.getOrNull()
            pendingShareFailed = share.isFailure
        }
    }

    // Con la app ya abierta (launchMode singleTop) la imagen llega aquí.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val share = readShare(intent) ?: return
        val path = share.getOrNull()
        if (path != null) shareChannel?.invokeMethod("image", path) else shareChannel?.invokeMethod("failed", null)
    }

    /// null si el intent no es una imagen compartida; si lo es, la ruta de la copia en caché.
    private fun readShare(intent: Intent?): Result<String>? {
        if (intent?.action != Intent.ACTION_SEND || intent.type?.startsWith("image/") != true) return null
        // Al reabrir desde recientes Android repite el intent original: esa imagen ya se leyó.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        return runCatching {
            // Restos de una copia vieja que nadie leyó (una reciente puede estar en uso).
            val stale = System.currentTimeMillis() - 60 * 60 * 1000
            cacheDir.listFiles { f -> f.name.startsWith("compartida_") && f.lastModified() < stale }?.forEach { it.delete() }
            @Suppress("DEPRECATION")
            val uri = (if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }) ?: throw IllegalStateException("Sin imagen")
            val out = File(cacheDir, "compartida_${java.util.UUID.randomUUID()}.jpg")
            try {
                val input = contentResolver.openInputStream(uri) ?: throw IllegalStateException("No se pudo abrir")
                input.use { src -> out.outputStream().use { dst -> src.copyTo(dst) } }
            } catch (e: Throwable) {
                out.delete() // no se deja una copia a medias
                throw e
            }
            // Ya consumida: recrear la actividad o girar la pantalla no la vuelve a leer.
            intent.action = Intent.ACTION_MAIN
            out.absolutePath
        }
    }

    private fun listenerEnabled(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(this, PaymentNotificationListener::class.java).flattenToString()
        return enabled.split(":").any { it == me }
    }

    /// Agrupa las líneas en renglones (de arriba abajo, de izquierda a derecha),
    /// para que "PATATAS BRAVAS" y "13,50" queden en la misma línea.
    private fun lines(text: Text): List<String> {
        val items = text.textBlocks.flatMap { it.lines }
            .mapNotNull { line -> line.boundingBox?.let { box -> box to line.text } }
            .sortedBy { it.first.centerY() }
        val rows = mutableListOf<MutableList<Pair<android.graphics.Rect, String>>>()
        for (item in items) {
            val reference = rows.lastOrNull()?.firstOrNull()
            if (reference != null && abs(reference.first.centerY() - item.first.centerY()) < reference.first.height() / 2) {
                rows.last().add(item)
            } else {
                rows.add(mutableListOf(item))
            }
        }
        return rows.map { row -> row.sortedBy { it.first.left }.joinToString(" ") { it.second } }
    }
}
