package com.example.stickerswap

import android.content.Context
import android.content.pm.ProviderInfo
import android.content.res.AssetFileDescriptor
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import com.example.stickerswap.whatsapp.StickerContentProvider
import com.example.stickerswap.whatsapp.StickerItem
import com.example.stickerswap.whatsapp.StickerPack
import com.example.stickerswap.whatsapp.StickerPackStorage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class StickerContentProviderSecurityTest {

    private lateinit var context: Context
    private lateinit var provider: StickerContentProvider
    private lateinit var validStickerFile: File

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        val info = ProviderInfo().apply {
            authority = StickerContentProvider.getAuthority(context.packageName)
        }
        provider = Robolectric.buildContentProvider(StickerContentProvider::class.java)
            .create(info)
            .get()

        val packDir = File(context.filesDir, "whatsapp_packs/test_pack").apply { mkdirs() }
        validStickerFile = File(packDir, "s1.webp").apply {
            writeBytes(byteArrayOf(0x52, 0x49, 0x46, 0x46))
        }
        val trayFile = File(packDir, "tray_test_pack.png").apply {
            writeBytes(byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47))
        }

        StickerPackStorage.saveOrUpdateStickerPack(
            context,
            StickerPack(
                identifier = "test_pack",
                name = "Test Pack",
                publisher = "StickerSwap",
                trayImage = trayFile.absolutePath,
                stickers = listOf(
                    StickerItem(validStickerFile.absolutePath, listOf("🔥"))
                ),
                animatedStickerPack = false
            )
        )
    }

    @Test
    fun `rejects shared_prefs and databases path traversal attempts`() {
        val dataRoot = context.filesDir.parentFile!!
        val sharedPrefsDir = File(dataRoot, "shared_prefs").apply { mkdirs() }
        val secretPrefs = File(sharedPrefsDir, "FlutterSecureStorage.xml").apply {
            writeText("<map><string name=\"token\">SECRET</string></map>")
        }
        val dbDir = File(dataRoot, "databases").apply { mkdirs() }
        val secretDb = File(dbDir, "stickers.db").apply { writeText("sqlite") }

        assertFalse(provider.isPathSandboxed(context, secretPrefs))
        assertFalse(provider.isPathSandboxed(context, secretDb))

        assertNull(provider.resolveAssetFile(context, "test_pack", secretPrefs.absolutePath))
        assertNull(provider.resolveAssetFile(context, "test_pack", "../shared_prefs/FlutterSecureStorage.xml"))
        assertNull(
            provider.resolveAssetFile(
                context,
                "test_pack",
                StickerPack.encodePath(secretPrefs.absolutePath)
            )
        )
        assertNull(provider.resolveAssetFile(context, "test_pack", "/etc/passwd"))
    }

    @Test
    fun `serves valid sticker file inside sandbox and returns UNKNOWN_LENGTH`() {
        assertTrue(provider.isPathSandboxed(context, validStickerFile))

        val resolved = provider.resolveAssetFile(
            context,
            "test_pack",
            StickerPack.encodePath(validStickerFile.absolutePath)
        )
        assertNotNull(resolved)
        assertEquals(validStickerFile.canonicalPath, resolved!!.canonicalPath)

        val authority = StickerContentProvider.getAuthority(context.packageName)
        val uri = Uri.parse(
            "content://$authority/stickers_asset/test_pack/${StickerPack.encodePath(validStickerFile.absolutePath)}"
        )
        val afd = provider.openAssetFile(uri, "r")
        assertNotNull(afd)
        assertEquals(AssetFileDescriptor.UNKNOWN_LENGTH, afd!!.declaredLength)
        afd.close()
    }

    @Test
    fun `stickers and metadata queries conform to WhatsApp column contracts`() {
        val authority = StickerContentProvider.getAuthority(context.packageName)
        val metaCursor = provider.query(
            Uri.parse("content://$authority/metadata/test_pack"),
            null,
            null,
            null,
            null
        )
        assertNotNull(metaCursor)
        metaCursor!!.use {
            assertTrue(it.moveToFirst())
            assertTrue(it.getColumnIndex("avoid_cache") >= 0)
            assertEquals("test_pack", it.getString(0))
        }

        val stickerCursor = provider.query(
            Uri.parse("content://$authority/stickers/test_pack"),
            null,
            null,
            null,
            null
        )
        assertNotNull(stickerCursor)
        stickerCursor!!.use {
            assertEquals(2, it.columnCount)
            assertEquals("sticker_file_name", it.getColumnName(0))
            assertEquals("sticker_emoji", it.getColumnName(1))
        }
    }
}

