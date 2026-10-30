package com.example.stickerswap.whatsapp

import android.content.ContentProvider
import android.content.ContentValues
import android.content.UriMatcher
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
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
        uriMatcher.addURI(authority, "stickers_asset/*/*", STICKER_ASSET)

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
                }
                cursor.setNotificationUri(context.contentResolver, uri)
                cursor
            }
            STICKERS_OF_PACK -> {
                val identifier = uri.lastPathSegment ?: return null
                val pack = StickerPackStorage.getStickerPack(context, identifier)
                val cursor = pack?.toStickersCursor() ?: MatrixCursor(StickerPack.STICKER_COLUMNS)
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
        if (matchCode != STICKER_ASSET) {
            throw FileNotFoundException("Invalid URI for asset: $uri")
        }

        val segments = uri.pathSegments
        if (segments.size < 3) {
            throw FileNotFoundException("Path too short: $uri")
        }

        val encodedPath = segments.last()
        val realPath = StickerPack.decodePath(encodedPath)
        var file = File(realPath)

        if (!file.exists()) {
            val context = context
            if (context != null) {
                val candidate = File(context.filesDir, encodedPath)
                if (candidate.exists()) {
                    file = candidate
                }
            }
        }

        if (!file.exists()) {
            Log.e(TAG, "Asset file not found on disk: $realPath (encoded: $encodedPath)")
            throw FileNotFoundException("File not found: $realPath")
        }

        return try {
            val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            AssetFileDescriptor(pfd, 0, file.length())
        } catch (e: Exception) {
            Log.e(TAG, "Error opening asset file: $realPath", e)
            throw FileNotFoundException("Cannot open asset file: $realPath")
        }
    }

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int {
        val context = context ?: return 0
        val matchCode = uriMatcher.match(uri)
        val identifier = when (matchCode) {
            METADATA_ONE, STICKERS_OF_PACK -> uri.lastPathSegment
            else -> uri.lastPathSegment
        }

        return if (!identifier.isNullOrEmpty()) {
            Log.d(TAG, "delete called for identifier: $identifier")
            StickerPackStorage.deleteStickerPack(context, identifier)
            try {
                context.contentResolver.notifyChange(uri, null)
            } catch (_: Exception) {}
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
