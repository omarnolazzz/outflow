package com.outflow.outflow

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureFilterTest {
    @Test
    fun detectaImportesConMoneda() {
        assertTrue(CaptureFilter.looksLikeMoney("Pagaste S/ 12.50"))
        assertTrue(CaptureFilter.looksLikeMoney("Netflix 9.99 USD"))
        assertTrue(CaptureFilter.looksLikeMoney("Consumo de US$ 1,250.00 en TIENDA"))
    }

    @Test
    fun ignoraTextoSinDinero() {
        assertFalse(CaptureFilter.looksLikeMoney("Tienes un mensaje"))
        assertFalse(CaptureFilter.looksLikeMoney(""))
        assertFalse(CaptureFilter.looksLikeMoney("Quedan 3 plazas"))
    }

    @Test
    fun filtroAmplioDejaLaDecisionADart() {
        val positivos = listOf(
            "Yapeaste 10 soles", "Pagaste 25 soles", "50 PEN", "10 USD", "Monto: 25.00",
            "Importe 25.00", "Pagaste 45.50", "Te enviaron £ 5", "Compra R\$ 20", "Cargo de 12 EUR",
            "PAGASTE 3", "Consumo 100", "Recibiste 20 dólares", "Recibiste 20 DOLARES", "Total 9,99",
            "Abono de 15 MXN", "Plineaste 8 soles",
        )
        for (t in positivos) assertTrue(t, CaptureFilter.looksLikeMoney(t))
        val negativos = listOf(
            "Tienes 3 mensajes", "Tu pedido llega en 10 minutos", "Pagaste", "Monto pendiente",
            "Hola", "Solo quedan 3 plazas",
        )
        for (t in negativos) assertFalse(t, CaptureFilter.looksLikeMoney(t))
    }

    @Test
    fun mismoTextoConOtraHoraEsOtroEvento() {
        val recent = RecentKeys()
        assertTrue(recent.firstTime("k", "Pagaste S/ 1", 100L))
        assertFalse(recent.firstTime("k", "Pagaste S/ 1", 100L))
        assertTrue(recent.firstTime("k", "Pagaste S/ 1", 200L))
    }

    @Test
    fun noRepiteLaMismaNotificacion() {
        val recent = RecentKeys(capacity = 2)
        assertTrue(recent.firstTime("k1", "Pagaste S/ 1", 1L))
        assertFalse(recent.firstTime("k1", "Pagaste S/ 1", 1L))
        // Misma clave con otro pago: es otra operación.
        assertTrue(recent.firstTime("k1", "Pagaste S/ 2", 1L))
        assertTrue(recent.firstTime("k2", "x", 1L))
        assertTrue(recent.firstTime("k3", "y", 1L))
        // k1 ya salió de la ventana.
        assertTrue(recent.firstTime("k1", "Pagaste S/ 2", 1L))
    }

    @Test
    fun apendeUnaLineaCompletaPorEvento() {
        val file = File.createTempFile("inbox", ".jsonl")
        file.delete()
        CaptureStore.appendLine(file, CaptureStore.eventJson("com.x", "X", "Título\nPagaste \"S/ 1\" ñ", "2026-11-03T10:00:00Z"))
        // Una línea cortada por un fallo no debe pegarse al siguiente evento.
        file.appendText("{\"sourceKey\":\"cor")
        CaptureStore.appendLine(file, CaptureStore.eventJson("com.y", "Y", "otro", "2026-11-03T10:01:00Z"))
        val lines = file.readText(Charsets.UTF_8).split("\n")
        assertEquals(4, lines.size)
        assertEquals("", lines.last())
        assertTrue(lines[0].contains('\\'.toString() + "n") && lines[0].contains("ñ"))
        assertTrue(lines[1].startsWith("{\"sourceKey\":\"cor"))
        assertTrue(lines[2].startsWith("{") && lines[2].contains("com.y"))
        file.delete()
    }
}
