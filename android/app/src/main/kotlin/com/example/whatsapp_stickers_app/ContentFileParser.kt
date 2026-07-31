package com.example.whatsapp_stickers_app

import android.content.Context
import org.json.JSONObject

/**
 * Lee y parsea /assets/contents.json usando org.json, que ya viene
 * incluido en el SDK de Android (no requiere ninguna dependencia extra).
 */
object ContentFileParser {
    private const val CONTENT_FILE_NAME = "contents.json"

    fun parseStickerPacks(context: Context): List<StickerPack> {
        val packs = mutableListOf<StickerPack>()

        context.assets.open(CONTENT_FILE_NAME).use { input ->
            val text = input.bufferedReader().use { it.readText() }
            val json = JSONObject(text)
            val packsArray = json.getJSONArray("sticker_packs")

            for (i in 0 until packsArray.length()) {
                val p = packsArray.getJSONObject(i)

                val pack = StickerPack(
                    identifier = p.getString("identifier"),
                    name = p.getString("name"),
                    publisher = p.getString("publisher"),
                    trayImageFile = p.getString("tray_image_file"),
                    androidPlayStoreLink = p.optString("android_play_store_link", ""),
                    iosAppStoreLink = p.optString("ios_app_store_link", ""),
                    publisherEmail = p.optString("publisher_email", ""),
                    publisherWebsite = p.optString("publisher_website", ""),
                    privacyPolicyWebsite = p.optString("privacy_policy_website", ""),
                    licenseAgreementWebsite = p.optString("license_agreement_website", ""),
                    imageDataVersion = p.optString("image_data_version", "1"),
                    avoidCache = p.optBoolean("avoid_cache", false),
                    animatedStickerPack = p.optBoolean("animated_sticker_pack", false)
                )

                val stickersArray = p.getJSONArray("stickers")
                for (j in 0 until stickersArray.length()) {
                    val s = stickersArray.getJSONObject(j)
                    val emojisArray = s.optJSONArray("emojis")
                    val emojis = mutableListOf<String>()
                    if (emojisArray != null) {
                        for (k in 0 until emojisArray.length()) {
                            emojis.add(emojisArray.getString(k))
                        }
                    }
                    pack.stickers.add(
                        Sticker(
                            imageFileName = s.getString("image_file"),
                            emojis = emojis,
                            accessibilityText = s.optString("accessibility_text", null)
                        )
                    )
                }

                packs.add(pack)
            }
        }

        return packs
    }
}
