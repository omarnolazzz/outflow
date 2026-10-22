package com.outflow.outflow

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat

/**
 * Lee las notificaciones de pago de Google Wallet y de los bancos y propone
 * registrar el gasto: publica un aviso de Outflow que abre la hoja de gasto
 * rellenada con `outflow://gasto?importe=…&comercio=…&tarjeta=…` (el mismo
 * camino que el atajo de Apple Pay en iPhone). Ignora cualquier otra app.
 */
class PaymentNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val source = SOURCES[sbn.packageName] ?: return
        val extras = sbn.notification.extras
        val title = extras.getCharSequence("android.title")?.toString().orEmpty()
        val text = (extras.getCharSequence("android.bigText") ?: extras.getCharSequence("android.text"))?.toString().orEmpty()
        val payment = PaymentParser.parse(title, text) ?: return
        propose(payment.amount, payment.merchant, source, sbn.key.hashCode())
    }

    private fun propose(amount: String, merchant: String, source: String, id: Int) {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Pagos detectados", NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
        val uri = Uri.Builder().scheme("outflow").authority("gasto")
            .appendQueryParameter("importe", amount)
            .appendQueryParameter("comercio", merchant)
            .appendQueryParameter("tarjeta", source)
            .build()
        val open = PendingIntent.getActivity(
            this, id,
            Intent(Intent.ACTION_VIEW, uri, this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val shown = if (merchant.isBlank()) amount else "$amount en $merchant"
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_outflow)
            .setContentTitle("¿Registrar este pago?")
            .setContentText("$shown · toca para guardarlo en Outflow")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        manager.notify(id, notification)
    }

    companion object {
        private const val CHANNEL = "outflow_pagos"

        /** Apps cuyas notificaciones de pago se leen → nombre que se guarda como tarjeta. */
        val SOURCES = mapOf(
            "com.google.android.apps.walletnfcrel" to "Google Wallet",
            "com.google.android.apps.nbu.paisa.user" to "Google Pay",
            "com.bcp.bank.bcp" to "BCP",
            "com.bcp.innovacxion.yapeapp" to "Yape",
            "pe.com.interbank.mobilebanking" to "Interbank",
            "com.bbva.nxt_peru" to "BBVA",
            "pe.com.scotiabank.blpm.android.client" to "Scotiabank",
        )
    }
}

/** Importe y comercio de una notificación de pago. */
data class DetectedPayment(val amount: String, val merchant: String)

object PaymentParser {
    private val amountRegex = Regex(
        """(S/\.?|PEN|US\$|USD|\$|€|EUR)\s?\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{1,2})?|\d{1,3}(?:[.,]\d{3})*[.,]\d{2}\s?(PEN|USD|EUR|soles)""",
        RegexOption.IGNORE_CASE,
    )
    private val merchantRegex = Regex("""\b(?:en|at|a)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ0-9 .&'*\-]{3,40}?)(?:\s+(?:con|with|el|on)\b|[.,]|$)""")

    /** null si el texto no parece un pago (sin importe con moneda). */
    fun parse(title: String, text: String): DetectedPayment? {
        val all = "$title $text"
        val amount = amountRegex.find(all)?.value ?: return null
        val merchant = merchantRegex.find(text)?.groupValues?.get(1)?.trim()
            ?: title.takeIf { it.isNotBlank() && amountRegex.find(it) == null }?.trim()
            ?: ""
        return DetectedPayment(amount, merchant)
    }
}
