# PdfBox carga recursos y clases por nombre: sin esto, leer un PDF falla solo en release.
-keep class com.tom_roush.pdfbox.** { *; }
-keep class com.tom_roush.fontbox.** { *; }
# Decodificador JPEG 2000 opcional de PdfBox: no se incluye porque solo se lee texto.
-dontwarn com.gemalto.jp2.**
