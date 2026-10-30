package com.example.stickerswap.whatsapp

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class WhatsAppMethodHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "com.example.stickerswap/whatsapp"
        const val REQUEST_CODE_ADD_STICKER = 2001
        private const val TAG = "WhatsAppMethodHandler"

        const val WHATSAPP_PACKAGE = "com.whatsapp"
        const val WHATSAPP_BUSINESS_PACKAGE = "com.whatsapp.w4b"
        const val ACTION_ENABLE_STICKER_PACK = "com.whatsapp.intent.action.ENABLE_STICKER_PACK"
        const val EXTRA_STICKER_PACK_ID = "sticker_pack_id"
        const val EXTRA_STICKER_PACK_AUTHORITY = "sticker_pack_authority"
        const val EXTRA_STICKER_PACK_NAME = "sticker_pack_name"
    }

    private var pendingAddResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = activity.applicationContext
        try {
            when (call.method) {
                "isWhatsAppInstalled" -> {
                    val installed = isPackageInstalled(WHATSAPP_PACKAGE, context.packageManager) ||
                            isPackageInstalled(WHATSAPP_BUSINESS_PACKAGE, context.packageManager)
                    result.success(installed)
                }
                "isPackInstalled" -> {
                    val identifier = call.argument<String>("identifier")
                    if (identifier.isNullOrEmpty()) {
                        result.success(false)
                        return
                    }
                    val isInstalled = checkPackInstalled(context, identifier)
                    result.success(isInstalled)
                }
                "addStickerPack" -> {
                    val argsMap = call.arguments as? Map<*, *>
                    if (argsMap == null) {
                        result.error("INVALID_ARGS", "Sticker pack arguments are null", null)
                        return
                    }

                    val json = JSONObject(argsMap)
                    val stickerPack = StickerPack.fromJson(json)

                    // 1. Save or update the pack metadata in local storage for ContentProvider
                    StickerPackStorage.saveOrUpdateStickerPack(context, stickerPack)

                    // 2. Prepare intent
                    val authority = StickerContentProvider.getAuthority(context.packageName)
                    val intent = Intent().apply {
                        action = ACTION_ENABLE_STICKER_PACK
                        putExtra(EXTRA_STICKER_PACK_ID, stickerPack.identifier)
                        putExtra(EXTRA_STICKER_PACK_AUTHORITY, authority)
                        putExtra(EXTRA_STICKER_PACK_NAME, stickerPack.name)
                    }

                    // Store pending result to complete when activity finishes
                    if (pendingAddResult != null) {
                        try {
                            pendingAddResult?.success(mapOf("status" to "cancelled", "success" to false))
                        } catch (_: Exception) {}
                        pendingAddResult = null
                    }
                    pendingAddResult = result

                    try {
                        val chooser = Intent.createChooser(intent, "WhatsApp'a Ekle")
                        activity.startActivityForResult(chooser, REQUEST_CODE_ADD_STICKER)
                    } catch (e: ActivityNotFoundException) {
                        pendingAddResult = null
                        result.error("WHATSAPP_NOT_FOUND", "WhatsApp is not installed", null)
                    } catch (e: Exception) {
                        pendingAddResult = null
                        result.error("INTENT_ERROR", e.localizedMessage, null)
                    }
                }
                "deleteStickerPack" -> {
                    val identifier = call.argument<String>("identifier")
                    if (identifier != null) {
                        StickerPackStorage.deleteStickerPack(context, identifier)
                    }
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in method call: ${call.method}", e)
            result.error("ERROR", e.localizedMessage, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE_ADD_STICKER) {
            return false
        }

        val resultCallback = pendingAddResult
        pendingAddResult = null

        if (resultCallback == null) {
            Log.w(TAG, "onActivityResult received but no pendingResult callback exists")
            return true
        }

        val validationError = data?.getStringExtra("validation_error")

        if (resultCode == Activity.RESULT_OK) {
            Log.d(TAG, "Sticker pack successfully added by user in WhatsApp")
            resultCallback.success(mapOf(
                "status" to "added",
                "success" to true
            ))
        } else if (resultCode == Activity.RESULT_CANCELED) {
            if (!validationError.isNullOrEmpty()) {
                Log.e(TAG, "WhatsApp sticker validation error: $validationError")
                resultCallback.success(mapOf(
                    "status" to "error",
                    "success" to false,
                    "error" to validationError
                ))
            } else {
                Log.d(TAG, "User cancelled adding sticker pack in WhatsApp dialog")
                resultCallback.success(mapOf(
                    "status" to "cancelled",
                    "success" to false
                ))
            }
        } else {
            resultCallback.success(mapOf(
                "status" to "unknown",
                "resultCode" to resultCode,
                "success" to false
            ))
        }

        return true
    }

    private fun isPackageInstalled(packageName: String, packageManager: PackageManager): Boolean {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            appInfo.enabled
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun checkPackInstalled(context: Context, identifier: String): Boolean {
        val authority = StickerContentProvider.getAuthority(context.packageName)
        val queryUri = Uri.Builder().scheme(ContentResolver.SCHEME_CONTENT)
            .authority("$WHATSAPP_PACKAGE.provider.sticker_whitelist_check")
            .appendPath("is_whitelisted")
            .appendQueryParameter("authority", authority)
            .appendQueryParameter("identifier", identifier)
            .build()

        return try {
            context.contentResolver.query(queryUri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex("result")
                    if (index >= 0) {
                        return cursor.getInt(index) == 1
                    }
                }
                false
            } ?: false
        } catch (_: Exception) {
            false
        }
    }
}

