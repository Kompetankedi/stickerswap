package com.example.stickerswap.whatsapp

import android.content.Context
import org.json.JSONArray
import java.io.File
import java.io.FileReader
import java.io.FileWriter

object StickerPackStorage {
    private const val FILE_NAME = "sticker_packs.json"

    private fun getFile(context: Context): File {
        return File(context.filesDir, FILE_NAME)
    }

    @Synchronized
    fun getStickerPacks(context: Context): MutableList<StickerPack> {
        val file = getFile(context)
        if (!file.exists()) {
            return mutableListOf()
        }

        return try {
            val content = FileReader(file).use { it.readText() }
            val jsonArray = JSONArray(content)
            val list = mutableListOf<StickerPack>()
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                list.add(StickerPack.fromJson(obj))
            }
            list
        } catch (e: Exception) {
            mutableListOf()
        }
    }

    @Synchronized
    fun getStickerPack(context: Context, identifier: String): StickerPack? {
        val packs = getStickerPacks(context)
        // 1. Exact match
        val exact = packs.firstOrNull { it.identifier == identifier }
        if (exact != null) return exact

        // 2. Fallback: match without trailing timestamp
        val cleanIdentifier = identifier.replace(Regex("_[0-9]{10,}$"), "")
        return packs.firstOrNull {
            it.identifier == cleanIdentifier ||
            it.identifier.replace(Regex("_[0-9]{10,}$"), "") == cleanIdentifier
        }
    }

    @Synchronized
    fun saveOrUpdateStickerPack(context: Context, pack: StickerPack) {
        val packs = getStickerPacks(context)
        val cleanId = pack.identifier.replace(Regex("_[0-9]{10,}$"), "")
        val existingIndex = packs.indexOfFirst {
            it.identifier == pack.identifier ||
            it.identifier.replace(Regex("_[0-9]{10,}$"), "") == cleanId
        }
        if (existingIndex != -1) {
            val existing = packs[existingIndex]
            val nextVersion = (existing.imageDataVersion.toIntOrNull() ?: 1) + 1
            pack.imageDataVersion = nextVersion.toString()
            packs[existingIndex] = pack
        } else {
            packs.add(pack)
        }
        saveAll(context, packs)
    }

    @Synchronized
    fun deleteStickerPack(context: Context, identifier: String) {
        val packs = getStickerPacks(context)
        val cleanIdentifier = identifier.replace(Regex("_[0-9]{10,}$"), "")
        val filtered = packs.filter {
            it.identifier != identifier &&
            it.identifier.replace(Regex("_[0-9]{10,}$"), "") != cleanIdentifier
        }
        if (filtered.size != packs.size) {
            saveAll(context, filtered)
        }
    }

    private fun saveAll(context: Context, packs: List<StickerPack>) {
        val jsonArray = JSONArray()
        packs.forEach { jsonArray.put(it.toJson()) }

        val file = getFile(context)
        FileWriter(file).use { writer ->
            writer.write(jsonArray.toString())
        }
    }
}
