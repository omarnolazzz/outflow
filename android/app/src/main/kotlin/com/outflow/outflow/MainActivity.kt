package com.outflow.outflow

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
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
