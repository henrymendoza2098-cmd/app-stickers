package com.example.whatsapp_stickers_app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "whatsapp_stickers_channel"

    private val addPackRequestCode = 200
    private val pickImageRequestCode = 300

    private var pendingAddPackResult: MethodChannel.Result? = null
    private var pendingPickImageResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "addStickerPack" -> handleAddStickerPack(call.argument("identifier"), call.argument("name"), result)
                    "pickImage" -> handlePickImage(result)
                    "getStickerPacks" -> result.success(StickerPackRepository.packsToJson(applicationContext))
                    "getPackTray" -> {
                        val identifier = call.argument<String>("identifier")
                        if (identifier == null) {
                            result.error("MISSING_ARGS", "Falta identifier", null)
                        } else {
                            result.success(StickerPackRepository.trayBytes(applicationContext, identifier))
                        }
                    }
                    "saveStickerPack" -> handleSaveStickerPack(call, result)
                    "deleteStickerPack" -> {
                        val identifier = call.argument<String>("identifier")
                        if (identifier == null) {
                            result.error("MISSING_ARGS", "Falta identifier", null)
                        } else {
                            StickerPackRepository.deletePack(applicationContext, identifier)
                            result.success(true)
                        }
                    }
                        "getProfile" -> {
                            result.success(ProfileRepository.getProfile(applicationContext).toString())
                        }
                        "saveProfile" -> {
                            val name = call.argument<String>("name")
                            val avatarBytes = call.argument<ByteArray>("avatarBytes")
                            val coverBytes = call.argument<ByteArray>("coverBytes")
                            ProfileRepository.saveProfile(applicationContext, name, avatarBytes, coverBytes)
                            result.success(true)
                        }
                        "getProfileAvatar" -> result.success(ProfileRepository.avatarBytes(applicationContext))
                        "getProfileCover" -> result.success(ProfileRepository.coverBytes(applicationContext))
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleAddStickerPack(identifier: String?, name: String?, result: MethodChannel.Result) {
        if (identifier == null || name == null) {
            result.error("MISSING_ARGS", "Faltan identifier o name", null)
            return
        }
        pendingAddPackResult = result
        val authority = "$packageName.stickercontentprovider"
        val intent = Intent().apply {
            action = "com.whatsapp.intent.action.ENABLE_STICKER_PACK"
            putExtra("sticker_pack_id", identifier)
            putExtra("sticker_pack_authority", authority)
            putExtra("sticker_pack_name", name)
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, addPackRequestCode)
        } catch (e: ActivityNotFoundException) {
            pendingAddPackResult?.error("WHATSAPP_NOT_FOUND", "WhatsApp no está instalado", null)
            pendingAddPackResult = null
        }
    }

    private fun handlePickImage(result: MethodChannel.Result) {
        pendingPickImageResult = result
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply { type = "image/*" }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, pickImageRequestCode)
        } catch (e: ActivityNotFoundException) {
            pendingPickImageResult?.error("NO_PICKER", "No se encontró un selector de imágenes", null)
            pendingPickImageResult = null
        }
    }

    private fun handleSaveStickerPack(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        try {
            val identifier = call.argument<String>("identifier")!!
            val name = call.argument<String>("name")!!
            val publisher = call.argument<String>("publisher") ?: ""
            val trayBytes = call.argument<ByteArray>("tray")!!

            @Suppress("UNCHECKED_CAST")
            val stickersArg = call.argument<List<Map<String, Any>>>("stickers")!!
            val stickers = stickersArg.map { m ->
                val bytes = m["bytes"] as ByteArray
                @Suppress("UNCHECKED_CAST")
                val emojisRaw = m["emojis"] as List<Any>
                val emojis = emojisRaw.map { it.toString() }
                Pair(bytes, emojis)
            }

            StickerPackRepository.savePack(applicationContext, identifier, name, publisher, trayBytes, stickers)
            result.success(true)
        } catch (e: Exception) {
            result.error("SAVE_ERROR", e.message, null)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            addPackRequestCode -> {
                when (resultCode) {
                    Activity.RESULT_OK -> pendingAddPackResult?.success("added")
                    Activity.RESULT_CANCELED -> {
                        val validationError = data?.getStringExtra("validation_error")
                        if (validationError != null) {
                            pendingAddPackResult?.error("VALIDATION_ERROR", validationError, null)
                        } else {
                            pendingAddPackResult?.success("cancelled")
                        }
                    }
                    else -> pendingAddPackResult?.success("unknown")
                }
                pendingAddPackResult = null
            }
            pickImageRequestCode -> {
                if (resultCode == Activity.RESULT_OK) {
                    val uri = data?.data
                    if (uri != null) {
                        try {
                            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                            if (bytes != null) {
                                pendingPickImageResult?.success(bytes)
                            } else {
                                pendingPickImageResult?.error("READ_ERROR", "No se pudo leer la imagen", null)
                            }
                        } catch (e: Exception) {
                            pendingPickImageResult?.error("READ_ERROR", e.message, null)
                        }
                    } else {
                        pendingPickImageResult?.success(null)
                    }
                } else {
                    pendingPickImageResult?.success(null)
                }
                pendingPickImageResult = null
            }
        }
    }
}
