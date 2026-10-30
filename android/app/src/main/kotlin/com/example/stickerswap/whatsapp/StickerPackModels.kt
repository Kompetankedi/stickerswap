package com.example.stickerswap.whatsapp

import android.database.MatrixCursor
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class StickerPack(
    val identifier: String,
    val name: String,
    val publisher: String,
    val trayImage: String,
    val stickers: List<StickerItem>,
    var imageDataVersion: String = "1",
    val animatedStickerPack: Boolean = false,
    val publisherEmail: String? = null,
    val publisherWebsite: String? = null,
    val privacyPolicyWebsite: String? = null,
    val licenseAgreementWebsite: String? = null,
    val iosAppStoreLink: String? = null,
    val androidPlayStoreLink: String? = null
) {
    companion object {
        val METADATA_COLUMNS = arrayOf(
            "sticker_pack_identifier",
            "sticker_pack_name",
            "sticker_pack_publisher",
            "sticker_pack_icon",
            "android_play_store_link",
            "ios_app_download_link",
            "sticker_pack_publisher_email",
            "sticker_pack_publisher_website",
            "sticker_pack_privacy_policy_website",
            "sticker_pack_license_agreement_website",
            "image_data_version",
            "whatsapp_will_not_cache_stickers",
            "animated_sticker_pack"
        )

        val STICKER_COLUMNS = arrayOf(
            "sticker_file_name",
            "sticker_emoji",
            "sticker_accessibility_text"
        )

        fun encodePath(path: String): String {
            return path.removePrefix("/").replace("/", "._.")
        }

        fun decodePath(encoded: String): String {
            val restored = encoded.replace("._.", File.separator)
            return if (!restored.startsWith(File.separator)) File.separator + restored else restored
        }

        fun fromJson(json: JSONObject): StickerPack {
            val identifier = json.getString("identifier")
            val name = json.getString("name")
            val publisher = json.getString("publisher")
            val trayImage = json.getString("trayImage")
            val imageDataVersion = json.optString("imageDataVersion", "1")
            val animatedStickerPack = json.optBoolean("animatedStickerPack", false)
            val publisherEmail = json.optString("publisherEmail").takeIf { it.isNotEmpty() }
            val publisherWebsite = json.optString("publisherWebsite").takeIf { it.isNotEmpty() }
            val privacyPolicyWebsite = json.optString("privacyPolicyWebsite").takeIf { it.isNotEmpty() }
            val licenseAgreementWebsite = json.optString("licenseAgreementWebsite").takeIf { it.isNotEmpty() }
            val iosAppStoreLink = json.optString("iosAppStoreLink").takeIf { it.isNotEmpty() }
            val androidPlayStoreLink = json.optString("androidPlayStoreLink").takeIf { it.isNotEmpty() }

            val stickersArray = json.getJSONArray("stickers")
            val stickers = mutableListOf<StickerItem>()
            for (i in 0 until stickersArray.length()) {
                val item = stickersArray.get(i)
                if (item is JSONObject) {
                    val path = item.getString("path")
                    val emojis = mutableListOf<String>()
                    val emojisArr = item.optJSONArray("emojis")
                    if (emojisArr != null) {
                        for (j in 0 until emojisArr.length()) {
                            emojis.add(emojisArr.getString(j))
                        }
                    }
                    stickers.add(StickerItem(path, emojis))
                } else if (item is String) {
                    stickers.add(StickerItem(item, listOf("⭐")))
                }
            }

            return StickerPack(
                identifier = identifier,
                name = name,
                publisher = publisher,
                trayImage = trayImage,
                stickers = stickers,
                imageDataVersion = imageDataVersion,
                animatedStickerPack = animatedStickerPack,
                publisherEmail = publisherEmail,
                publisherWebsite = publisherWebsite,
                privacyPolicyWebsite = privacyPolicyWebsite,
                licenseAgreementWebsite = licenseAgreementWebsite,
                iosAppStoreLink = iosAppStoreLink,
                androidPlayStoreLink = androidPlayStoreLink
            )
        }
    }

    fun toJson(): JSONObject {
        val json = JSONObject()
        json.put("identifier", identifier)
        json.put("name", name)
        json.put("publisher", publisher)
        json.put("trayImage", trayImage)
        json.put("imageDataVersion", imageDataVersion)
        json.put("animatedStickerPack", animatedStickerPack)
        json.put("publisherEmail", publisherEmail ?: "")
        json.put("publisherWebsite", publisherWebsite ?: "")
        json.put("privacyPolicyWebsite", privacyPolicyWebsite ?: "")
        json.put("licenseAgreementWebsite", licenseAgreementWebsite ?: "")
        json.put("iosAppStoreLink", iosAppStoreLink ?: "")
        json.put("androidPlayStoreLink", androidPlayStoreLink ?: "")

        val stickersArr = JSONArray()
        stickers.forEach { sticker ->
            val sObj = JSONObject()
            sObj.put("path", sticker.path)
            val emojisArr = JSONArray()
            sticker.emojis.forEach { emojisArr.put(it) }
            sObj.put("emojis", emojisArr)
            stickersArr.put(sObj)
        }
        json.put("stickers", stickersArr)
        return json
    }

    fun toMetadataRow(): Array<Any?> {
        return arrayOf(
            identifier,
            name,
            publisher,
            encodePath(trayImage),
            androidPlayStoreLink ?: "",
            iosAppStoreLink ?: "",
            publisherEmail ?: "",
            publisherWebsite ?: "",
            privacyPolicyWebsite ?: "",
            licenseAgreementWebsite ?: "",
            imageDataVersion,
            0,
            if (animatedStickerPack) 1 else 0
        )
    }

    fun toStickersCursor(): MatrixCursor {
        val cursor = MatrixCursor(STICKER_COLUMNS)
        stickers.forEach { sticker ->
            val emojiStr = sticker.emojis.joinToString(",")
            cursor.addRow(
                arrayOf(
                    encodePath(sticker.path),
                    emojiStr,
                    ""
                )
            )
        }
        return cursor
    }
}

data class StickerItem(
    val path: String,
    val emojis: List<String> = emptyList()
)
