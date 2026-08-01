package com.example.whatsapp_stickers_app

import android.content.Context
import org.json.JSONObject
import java.io.File
import kotlin.random.Random

/**
 * Guarda el perfil local del usuario (nombre, username autogenerado,
 * foto principal y foto de portada) en el almacenamiento privado de la
 * app. El username se genera una sola vez la primera vez que se lee el
 * perfil, y luego queda fijo (igual que el "stickerlyXXXXXXXX" de
 * Sticker.ly) — el usuario no lo puede cambiar.
 */
object ProfileRepository {
    private const val PROFILE_FILE_NAME = "profile.json"
    private const val AVATAR_FILE_NAME = "profile_avatar.png"
    private const val COVER_FILE_NAME = "profile_cover.png"

    private fun profileFile(context: Context) = File(context.filesDir, PROFILE_FILE_NAME)

    private fun generateUsername(): String {
        val n = Random.nextInt(10_000_000, 99_999_999)
        return "stickerly$n"
    }

    /** Devuelve el perfil como JSON: { name, username, hasAvatar, hasCover } */
    fun getProfile(context: Context): JSONObject {
        val file = profileFile(context)
        val json: JSONObject
        if (file.exists()) {
            json = JSONObject(file.readText())
            if (!json.has("bio")) {
                json.put("bio", "")
                file.writeText(json.toString())
            }
        } else {
            json = JSONObject()
            json.put("name", "")
            json.put("username", generateUsername())
            json.put("bio", "")
            file.writeText(json.toString())
        }
        json.put("hasAvatar", File(context.filesDir, AVATAR_FILE_NAME).exists())
        json.put("hasCover", File(context.filesDir, COVER_FILE_NAME).exists())
        return json
    }

    fun saveProfile(context: Context, name: String?, bio: String?, avatarBytes: ByteArray?, coverBytes: ByteArray?) {
        val current = getProfile(context)
        if (name != null) current.put("name", name)
        if (bio != null) current.put("bio", bio)
        current.remove("hasAvatar")
        current.remove("hasCover")
        profileFile(context).writeText(current.toString())

        if (avatarBytes != null) {
            File(context.filesDir, AVATAR_FILE_NAME).writeBytes(avatarBytes)
        }
        if (coverBytes != null) {
            File(context.filesDir, COVER_FILE_NAME).writeBytes(coverBytes)
        }
    }

    fun avatarBytes(context: Context): ByteArray? {
        val f = File(context.filesDir, AVATAR_FILE_NAME)
        return if (f.exists()) f.readBytes() else null
    }

    fun coverBytes(context: Context): ByteArray? {
        val f = File(context.filesDir, COVER_FILE_NAME)
        return if (f.exists()) f.readBytes() else null
    }
}
