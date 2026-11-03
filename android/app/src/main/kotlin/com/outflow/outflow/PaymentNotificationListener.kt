package com.outflow.outflow

import android.app.Notification
import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Lee en silencio las notificaciones con pinta de pago de las apps activadas y
 * las deja en la bandeja privada de captura; Dart las lee al abrir la app.
 * De una app no activada solo se apunta que existe (paquete y nombre), nunca su texto.
 * No muestra nada ni escribe el texto en los registros.
 */
class PaymentNotificationListener : NotificationListenerService() {
    private val recent = RecentKeys()

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName) return
        val notification = sbn.notification
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()
        val body = big.ifBlank { extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty() }
        val text = listOf(title, body).filter { it.isNotBlank() }.joinToString("\n")
        if (!CaptureFilter.looksLikeMoney(text)) return

        val label = appLabel(sbn.packageName)
        if (!CaptureStore.isEnabled(this, sbn.packageName)) {
            CaptureStore.noteSeen(this, sbn.packageName, label)
            return
        }
        if (!recent.firstTime(sbn.key, text, sbn.postTime)) return
        try {
            CaptureStore.append(this, sbn.packageName, label, text, sbn.postTime)
        } catch (_: Exception) {
            // Sin el error: podría citar el texto. La notificación original sigue en la barra.
        }
    }

    private fun appLabel(packageName: String): String =
        CaptureStore.SOURCES[packageName] ?: try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(packageName, 0)).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            packageName
        }
}
