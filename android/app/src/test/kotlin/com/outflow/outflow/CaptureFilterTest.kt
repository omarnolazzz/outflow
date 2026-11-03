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
    fun noRepiteLaMismaNotificacion() {
        val recent = RecentKeys(capacity = 2)
        assertTrue(recent.firstTime("k1", "Pagaste S/ 1"))
        assertFalse(recent.firstTime("k1", "Pagaste S/ 1"))
        // Misma clave con otro pago: es otra operación.
        assertTrue(recent.firstTime("k1", "Pagaste S/ 2"))
        assertTrue(recent.firstTime("k2", "x"))
        assertTrue(recent.firstTime("k3", "y"))
        // k1 ya salió de la ventana.
        assertTrue(recent.firstTime("k1", "Pagaste S/ 2"))
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
