package com.thanhhao.esp32_navride

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.io.File

/** Mã hóa lại pixel để bỏ EXIF/GPS, ảnh thu nhỏ và tên tệp cá nhân. */
internal object MarkerPhoto {
    const val MAX_BYTES = 150 * 1024
    fun compress(file: File): ByteArray {
        require(file.length() in 1..30_000_000) { "Could not read the photo" }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Invalid photo" }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 1600) sample *= 2
        var bitmap = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: throw IllegalArgumentException("Could not decode the photo")
        try {
            val orientation = ExifInterface(file.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)
            val matrix = Matrix().apply {
                when (orientation) {
                    2 -> setScale(-1f, 1f)
                    3 -> setRotate(180f)
                    4 -> setScale(1f, -1f)
                    5 -> { setRotate(90f); postScale(-1f, 1f) }
                    6 -> setRotate(90f)
                    7 -> { setRotate(270f); postScale(-1f, 1f) }
                    8 -> setRotate(270f)
                }
            }
            if (!matrix.isIdentity) {
                val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                if (rotated !== bitmap) { bitmap.recycle(); bitmap = rotated }
            }
            var size = 960
            while (true) {
                val ratio = minOf(1.0, size.toDouble() / maxOf(bitmap.width, bitmap.height))
                val scaled = Bitmap.createScaledBitmap(bitmap, maxOf(1, (bitmap.width * ratio).toInt()),
                    maxOf(1, (bitmap.height * ratio).toInt()), true)
                try {
                    for (quality in intArrayOf(80, 65, 50, 35)) {
                        val output = ByteArrayOutputStream()
                        check(scaled.compress(Bitmap.CompressFormat.JPEG, quality, output))
                        val bytes = output.toByteArray()
                        if (bytes.size <= MAX_BYTES) return bytes
                    }
                } finally { if (scaled !== bitmap) scaled.recycle() }
                check(size > 240) { "Photo is too large. Try a simpler photo" }
                size /= 2
            }
        } finally { bitmap.recycle() }
    }
}
