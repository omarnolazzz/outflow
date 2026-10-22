package com.outflow.outflow

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PaymentParserTest {
    @Test
    fun googleWallet() {
        val p = PaymentParser.parse("Starbucks", "S/ 12.50 con Visa ••••1234")!!
        assertEquals("S/ 12.50", p.amount)
        assertEquals("Starbucks", p.merchant)
    }

    @Test
    fun bankWithMerchantInText() {
        val p = PaymentParser.parse("Consumo con tu tarjeta", "Realizaste un consumo de S/ 45.90 en PLAZA VEA SURCO con tu tarjeta")!!
        assertEquals("S/ 45.90", p.amount)
        assertEquals("PLAZA VEA SURCO", p.merchant)
    }

    @Test
    fun dollarsAfterAmount() {
        assertEquals("9.99 USD", PaymentParser.parse("Netflix", "Pagaste 9.99 USD")!!.amount)
    }

    @Test
    fun notAPayment() {
        assertNull(PaymentParser.parse("Promoción", "Tienes un nuevo beneficio"))
    }
}
