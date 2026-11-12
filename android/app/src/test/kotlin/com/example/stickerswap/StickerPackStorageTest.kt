package com.example.stickerswap

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.example.stickerswap.whatsapp.StickerItem
import com.example.stickerswap.whatsapp.StickerPack
import com.example.stickerswap.whatsapp.StickerPackStorage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class StickerPackStorageTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        File(context.filesDir, "sticker_packs.json").delete()
    }

    @Test
    fun `saves updates increments version and isolates multi-part packs`() {
        val part1 = StickerPack(
            identifier = "CatsPack_part1",
            name = "Cats Part 1",
            publisher = "Pub",
            trayImage = "/tmp/tray1.png",
            stickers = listOf(StickerItem("/tmp/1.webp", listOf("🐱")))
        )
        val part2 = StickerPack(
            identifier = "CatsPack_part2",
            name = "Cats Part 2",
            publisher = "Pub",
            trayImage = "/tmp/tray2.png",
            stickers = listOf(StickerItem("/tmp/2.webp", listOf("😸")))
        )

        StickerPackStorage.saveOrUpdateStickerPack(context, part1)
        StickerPackStorage.saveOrUpdateStickerPack(context, part2)

        assertEquals(2, StickerPackStorage.getStickerPacks(context).size)
        assertEquals("Cats Part 2", StickerPackStorage.getStickerPack(context, "CatsPack_part2")?.name)
        assertNull(StickerPackStorage.getStickerPack(context, "CatsPack_part3"))

        // Updating part1 with a versioned timestamp should bump imageDataVersion and replace cleanly
        val updatedPart1 = part1.copy(
            identifier = "CatsPack_part1_1741512345",
            name = "Cats Part 1 Edited"
        )
        StickerPackStorage.saveOrUpdateStickerPack(context, updatedPart1)

        val reloaded = StickerPackStorage.getStickerPack(context, "CatsPack_part1")
        assertNotNull(reloaded)
        assertEquals("Cats Part 1 Edited", reloaded!!.name)
        assertEquals("2", reloaded.imageDataVersion)
    }

    @Test
    fun `returns empty list cleanly on corrupt storage json`() {
        File(context.filesDir, "sticker_packs.json").writeText("{corrupt_json_not_array")

        val packs = StickerPackStorage.getStickerPacks(context)
        assertTrue(packs.isEmpty())
    }

    @Test
    fun `deletes pack by timestamp-suffixed identifier`() {
        val pack = StickerPack(
            identifier = "MemePack_1741512999",
            name = "Memes",
            publisher = "Pub",
            trayImage = "/tmp/tray.png",
            stickers = listOf(StickerItem("/tmp/m.webp", listOf("😂")))
        )
        StickerPackStorage.saveOrUpdateStickerPack(context, pack)
        assertEquals(1, StickerPackStorage.getStickerPacks(context).size)

        StickerPackStorage.deleteStickerPack(context, "MemePack")
        assertTrue(StickerPackStorage.getStickerPacks(context).isEmpty())
    }
}

