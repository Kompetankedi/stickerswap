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
        val decodedId = try { android.net.Uri.decode(identifier) } catch (_: Exception) { identifier }

        // 1. Exact match on raw or decoded identifier
        val exact = packs.firstOrNull { it.identifier == identifier || it.identifier == decodedId }
        if (exact != null) return exact

        // 2. Match without trailing timestamp (_1741512345)
        val cleanIdentifier = identifier.replace(Regex("_[0-9]{10,}$"), "")
        val cleanDecoded = decodedId.replace(Regex("_[0-9]{10,}$"), "")
        val matchWithoutTimestamp = packs.firstOrNull {
            val pClean = it.identifier.replace(Regex("_[0-9]{10,}$"), "")
            it.identifier == cleanIdentifier ||
            it.identifier == cleanDecoded ||
            pClean == cleanIdentifier ||
            pClean == cleanDecoded
        }
        if (matchWithoutTimestamp != null) return matchWithoutTimestamp

        // 3. Case-insensitive match (with/without timestamp)
        val matchCaseInsensitive = packs.firstOrNull {
            val pClean = it.identifier.replace(Regex("_[0-9]{10,}$"), "")
            it.identifier.equals(identifier, ignoreCase = true) ||
            it.identifier.equals(decodedId, ignoreCase = true) ||
            pClean.equals(cleanIdentifier, ignoreCase = true) ||
            pClean.equals(cleanDecoded, ignoreCase = true)
        }
        if (matchCaseInsensitive != null) return matchCaseInsensitive

        // 4. Multi-part packs: if identifier has a specific _partX, DO NOT fall back to other parts!
        val partMatch = Regex("_part([0-9]+)", RegexOption.IGNORE_CASE).find(cleanIdentifier)
            ?: Regex("_part([0-9]+)", RegexOption.IGNORE_CASE).find(cleanDecoded)

        if (partMatch != null) {
            val partNum = partMatch.groupValues[1]
            val baseId = cleanIdentifier.replace(Regex("_part[0-9]+.*", RegexOption.IGNORE_CASE), "")
            return packs.firstOrNull { pack ->
                val pClean = pack.identifier.replace(Regex("_[0-9]{10,}$"), "")
                val pBase = pClean.replace(Regex("_part[0-9]+.*", RegexOption.IGNORE_CASE), "")
                val pPartMatch = Regex("_part([0-9]+)", RegexOption.IGNORE_CASE).find(pClean)
                (pBase.equals(baseId, ignoreCase = true)) && (pPartMatch?.groupValues?.get(1) == partNum)
            }
        }

        // 5. Single-pack query fallback: ONLY if no part suffix was specified
        val baseId = cleanIdentifier.replace(Regex("_part[0-9]+.*"), "")
        return packs.firstOrNull {
            val pClean = it.identifier.replace(Regex("_[0-9]{10,}$"), "")
            it.identifier.equals(baseId, ignoreCase = true) ||
            pClean.equals(baseId, ignoreCase = true)
        }
    }

    @Synchronized
    fun saveOrUpdateStickerPack(context: Context, pack: StickerPack) {
        val packs = getStickerPacks(context)
        val cleanId = pack.identifier.replace(Regex("_[0-9]{10,}$"), "")
        val existingIndex = packs.indexOfFirst {
            val itClean = it.identifier.replace(Regex("_[0-9]{10,}$"), "")
            it.identifier == pack.identifier ||
            it.identifier == cleanId ||
            itClean == cleanId ||
            itClean.equals(cleanId, ignoreCase = true)
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
        val decodedId = try { android.net.Uri.decode(identifier) } catch (_: Exception) { identifier }
        val cleanIdentifier = identifier.replace(Regex("_[0-9]{10,}$"), "")
        val cleanDecoded = decodedId.replace(Regex("_[0-9]{10,}$"), "")

        val filtered = packs.filterNot { pack ->
            val pClean = pack.identifier.replace(Regex("_[0-9]{10,}$"), "")
            pack.identifier == identifier ||
            pack.identifier == decodedId ||
            pack.identifier == cleanIdentifier ||
            pack.identifier == cleanDecoded ||
            pClean == cleanIdentifier ||
            pClean == cleanDecoded ||
            pack.identifier.equals(cleanIdentifier, ignoreCase = true) ||
            pClean.equals(cleanIdentifier, ignoreCase = true)
        }
        if (filtered.size != packs.size) {
            saveAll(context, filtered.toMutableList())
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
