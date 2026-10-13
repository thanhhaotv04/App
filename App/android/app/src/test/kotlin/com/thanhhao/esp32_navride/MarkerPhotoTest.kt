package com.thanhhao.esp32_navride

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ExifInterface
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class MarkerPhotoTest {
    @Test fun reencodesPhotoWithinLimitAndStripsGpsExif() {
        val cache = RuntimeEnvironment.getApplication().cacheDir
        val input = File.createTempFile("marker-input-", ".jpg", cache)
        val output = File.createTempFile("marker-output-", ".jpg", cache)
        try {
            val bitmap = Bitmap.createBitmap(1400, 1100, Bitmap.Config.ARGB_8888)
            input.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)) }
            bitmap.recycle()
            ExifInterface(input.path).apply {
                setAttribute(ExifInterface.TAG_GPS_LATITUDE, "10/1,46/1,0/1")
                setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, "N")
                setAttribute(ExifInterface.TAG_GPS_LONGITUDE, "106/1,42/1,0/1")
                setAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF, "E")
                saveAttributes()
            }
            assertNotNull(ExifInterface(input.path).getAttribute(ExifInterface.TAG_GPS_LATITUDE))
            val bytes = MarkerPhoto.compress(input)
            assertTrue(bytes.size in 1..MarkerPhoto.MAX_BYTES)
            output.writeBytes(bytes)
            assertNull(ExifInterface(output.path).getAttribute(ExifInterface.TAG_GPS_LATITUDE))
            val decoded = BitmapFactory.decodeFile(output.path)
            assertTrue(maxOf(decoded.width, decoded.height) <= 960)
            decoded.recycle()
        } finally { input.delete(); output.delete() }
    }
}
