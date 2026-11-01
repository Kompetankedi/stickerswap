package com.example.stickerswap.whatsapp

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.UriMatcher
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.io.FileNotFoundException

class StickerContentProvider : ContentProvider() {
    companion object {
        private const val TAG = "StickerContentProvider"
        private const val METADATA_ALL = 1
        private const val METADATA_ONE = 2
        private const val STICKERS_OF_PACK = 3
        private const val STICKER_ASSET = 4

        private val uriMatcher = UriMatcher(UriMatcher.NO_MATCH)

        fun getAuthority(packageName: String): String {
            return "$packageName.stickercontentprovider"
        }
    }

    override fun onCreate(): Boolean {
        val context = context ?: return false
        val authority = getAuthority(context.packageName)

        uriMatcher.addURI(authority, "metadata", METADATA_ALL)
        uriMatcher.addURI(authority, "metadata/*", METADATA_ONE)
        uriMatcher.addURI(authority, "stickers/*", STICKERS_OF_PACK)
        uriMatcher.addURI(authority, "stickers_asset/*", STICKER_ASSET)
        uriMatcher.addURI(authority, "stickers_asset/*/*", STICKER_ASSET)
        uriMatcher.addURI(authority, "stickers_asset/*/*/*", STICKER_ASSET)

        Log.d(TAG, "Initialized StickerContentProvider with authority: $authority")
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        val context = context ?: return null
        return when (uriMatcher.match(uri)) {
            METADATA_ALL -> {
                val packs = StickerPackStorage.getStickerPacks(context)
                val cursor = MatrixCursor(StickerPack.METADATA_COLUMNS)
                packs.forEach { cursor.addRow(it.toMetadataRow()) }
                cursor.setNotificationUri(context.contentResolver, uri)
                cursor
            }
            METADATA_ONE -> {
                val identifier = uri.lastPathSegment ?: return null
                val pack = StickerPackStorage.getStickerPack(context, identifier)
                val cursor = MatrixCursor(StickerPack.METADATA_COLUMNS)
                if (pack != null) {
                    cursor.addRow(pack.toMetadataRow())
                } else {
                    // Safe fallback metadata row for legacy/orphan packs so WhatsApp validator doesn't abort
                    Log.w(TAG, "Pack $identifier not in storage; returning fallback metadata row for WhatsApp")
                    cursor.addRow(StickerPack.createFallbackMetadataRow(identifier))
                }
                cursor.setNotificationUri(context.contentResolver, uri)
                cursor
            }
            STICKERS_OF_PACK -> {
                val identifier = uri.lastPathSegment ?: return null
                val pack = StickerPackStorage.getStickerPack(context, identifier)
                val cursor = pack?.toStickersCursor() ?: run {
                    Log.w(TAG, "Pack $identifier not in storage; returning fallback stickers cursor for WhatsApp")
                    StickerPack.createFallbackStickersCursor(identifier)
                }
                cursor.setNotificationUri(context.contentResolver, uri)
                cursor
            }
            else -> {
                Log.w(TAG, "Unknown query URI: $uri")
                null
            }
        }
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        val afd = openAssetFile(uri, mode) ?: return null
        return afd.parcelFileDescriptor
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? {
        val matchCode = uriMatcher.match(uri)
        if (matchCode != STICKER_ASSET && !(uri.path ?: "").contains("stickers_asset")) {
            throw FileNotFoundException("Invalid URI for asset: $uri")
        }

        val segments = uri.pathSegments
        if (segments.isEmpty()) {
            throw FileNotFoundException("Path empty: $uri")
        }

        val context = context ?: throw FileNotFoundException("Context is null")
        val fileName = segments.last()
        val identifier = if (segments.size >= 3) segments[segments.size - 2] else null

        val file = resolveAssetFile(context, identifier, fileName)
        if (file != null && file.exists()) {
            return try {
                val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                AssetFileDescriptor(pfd, 0, file.length())
            } catch (e: Exception) {
                Log.e(TAG, "Error opening asset file: ${file.absolutePath}, falling back to placeholder", e)
                getOrCreateFallbackAsset(context, fileName)
            }
        }

        Log.w(TAG, "Asset file not found on disk: $fileName (identifier: $identifier). Serving fallback placeholder.")
        return getOrCreateFallbackAsset(context, fileName)
    }

    private fun resolveAssetFile(context: Context, identifier: String?, fileName: String): File? {
        // 1. Direct path check
        if (fileName.startsWith(File.separator)) {
            val direct = File(fileName)
            if (direct.exists()) return direct
        }

        // 2. Encoded path check (e.g., data._.user._.0._...)
        val decodedPath = StickerPack.decodePath(fileName)
        val decodedFile = File(decodedPath)
        if (decodedFile.exists()) return decodedFile

        // 3. Search via StickerPackStorage if identifier is available
        if (!identifier.isNullOrEmpty()) {
            val pack = StickerPackStorage.getStickerPack(context, identifier)
            if (pack != null) {
                // Is it the tray icon?
                if (fileName.contains("tray", ignoreCase = true) ||
                    File(pack.trayImage).name == fileName ||
                    pack.trayImage.endsWith(fileName) ||
                    StickerPack.encodePath(pack.trayImage) == fileName
                ) {
                    val tray = File(pack.trayImage)
                    if (tray.exists()) return tray
                }

                // Is it one of the stickers?
                val stickerMatch = pack.stickers.firstOrNull {
                    File(it.path).name == fileName ||
                    it.path.endsWith(fileName) ||
                    StickerPack.encodePath(it.path) == fileName
                }
                if (stickerMatch != null) {
                    val sFile = File(stickerMatch.path)
                    if (sFile.exists()) return sFile
                }

                // Try numeric index matching (e.g. "0.webp", "0", "00_...", "sticker_1.webp")
                val numericMatch = Regex("([0-9]+)").find(fileName)
                if (numericMatch != null) {
                    val rawNum = numericMatch.value.toIntOrNull()
                    if (rawNum != null) {
                        val idx0 = if (fileName.startsWith("sticker_")) rawNum - 1 else rawNum
                        if (idx0 in pack.stickers.indices) {
                            val candidate = File(pack.stickers[idx0].path)
                            if (candidate.exists()) return candidate
                        }
                    }
                }
            }
        }

        // 4. Candidate directories in Flutter and native storage
        val baseCandidateDirs = mutableListOf<File>()
        val appFlutterDir = File(context.applicationInfo.dataDir, "app_flutter")
        baseCandidateDirs.add(File(appFlutterDir, "whatsapp_packs"))
        baseCandidateDirs.add(File(context.filesDir, "whatsapp_packs"))
        baseCandidateDirs.add(File(context.cacheDir, "whatsapp_packs"))
        baseCandidateDirs.add(File(appFlutterDir, "stickers"))
        baseCandidateDirs.add(File(context.filesDir, "stickers"))

        val cleanName = File(decodedPath).name

        for (baseDir in baseCandidateDirs) {
            if (!baseDir.exists()) continue

            // 4a. If identifier given, check pack folder
            if (!identifier.isNullOrEmpty()) {
                val packDir1 = File(baseDir, identifier)
                if (packDir1.exists()) {
                    val f1 = File(packDir1, fileName)
                    if (f1.exists()) return f1
                    val f2 = File(packDir1, cleanName)
                    if (f2.exists()) return f2
                }
                // Check without _part suffix (e.g. AzizKediler_by_fStikBot_part2 -> AzizKediler_by_fStikBot)
                val basePackId = identifier.replace(Regex("_part[0-9]+.*"), "")
                if (basePackId != identifier) {
                    val packDir2 = File(baseDir, basePackId)
                    if (packDir2.exists()) {
                        val f1 = File(packDir2, fileName)
                        if (f1.exists()) return f1
                        val f2 = File(packDir2, cleanName)
                        if (f2.exists()) return f2
                    }
                }
            }

            // 4b. Direct file inside baseDir
            val directInBase = File(baseDir, fileName)
            if (directInBase.exists()) return directInBase
            val cleanInBase = File(baseDir, cleanName)
            if (cleanInBase.exists()) return cleanInBase

            // 4c. Search subdirectories
            val subdirs = baseDir.listFiles { f -> f.isDirectory } ?: emptyArray()
            for (sub in subdirs) {
                val candidate = File(sub, cleanName)
                if (candidate.exists()) return candidate
                val candidateRaw = File(sub, fileName)
                if (candidateRaw.exists()) return candidateRaw
            }
        }

        // 5. Check across all known sticker packs in storage
        val allPacks = StickerPackStorage.getStickerPacks(context)
        for (p in allPacks) {
            if (File(p.trayImage).name == cleanName) {
                val f = File(p.trayImage)
                if (f.exists()) return f
            }
            for (s in p.stickers) {
                if (File(s.path).name == cleanName) {
                    val f = File(s.path)
                    if (f.exists()) return f
                }
            }
        }

        return null
    }

    private fun getOrCreateFallbackAsset(context: Context, fileName: String): AssetFileDescriptor? {
        return try {
            val fallbackDir = File(context.cacheDir, "fallback_stickers")
            if (!fallbackDir.exists()) fallbackDir.mkdirs()

            val isPng = fileName.endsWith(".png", ignoreCase = true) || fileName.contains("tray", ignoreCase = true)
            val targetFile = if (isPng) {
                File(fallbackDir, "fallback_tray.png")
            } else {
                File(fallbackDir, "fallback_sticker.webp")
            }

            if (!targetFile.exists() || targetFile.length() == 0L) {
                val size = if (isPng) 96 else 512
                val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                targetFile.outputStream().use { out ->
                    if (isPng) {
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                    } else {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            bitmap.compress(Bitmap.CompressFormat.WEBP_LOSSLESS, 100, out)
                        } else {
                            @Suppress("DEPRECATION")
                            bitmap.compress(Bitmap.CompressFormat.WEBP, 100, out)
                        }
                    }
                }
                bitmap.recycle()
            }

            val pfd = ParcelFileDescriptor.open(targetFile, ParcelFileDescriptor.MODE_READ_ONLY)
            AssetFileDescriptor(pfd, 0, targetFile.length())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create fallback asset for $fileName", e)
            null
        }
    }

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int {
        val context = context ?: return 0
        val matchCode = uriMatcher.match(uri)
        val identifier = when (matchCode) {
            METADATA_ONE, STICKERS_OF_PACK -> uri.lastPathSegment
            else -> uri.lastPathSegment ?: selectionArgs?.firstOrNull() ?: selection
        }

        return if (!identifier.isNullOrEmpty()) {
            Log.d(TAG, "delete called for identifier: $identifier")
            StickerPackStorage.deleteStickerPack(context, identifier)
            try {
                val authority = getAuthority(context.packageName)
                context.contentResolver.notifyChange(Uri.parse("content://$authority/metadata"), null)
                context.contentResolver.notifyChange(Uri.parse("content://$authority/metadata/$identifier"), null)
                context.contentResolver.notifyChange(Uri.parse("content://$authority/stickers/$identifier"), null)
                context.contentResolver.notifyChange(uri, null)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to notify change on delete", e)
            }
            1
        } else {
            0
        }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    override fun getType(uri: Uri): String? {
        val context = context ?: return null
        val authority = getAuthority(context.packageName)

        return when (uriMatcher.match(uri)) {
            METADATA_ALL -> "vnd.android.cursor.dir/vnd.$authority.metadata"
            METADATA_ONE -> "vnd.android.cursor.item/vnd.$authority.metadata"
            STICKERS_OF_PACK -> "vnd.android.cursor.dir/vnd.$authority.stickers"
            STICKER_ASSET -> {
                val path = uri.path ?: ""
                if (path.endsWith(".png", ignoreCase = true)) {
                    "image/png"
                } else {
                    "image/webp"
                }
            }
            else -> null
        }
    }
}
