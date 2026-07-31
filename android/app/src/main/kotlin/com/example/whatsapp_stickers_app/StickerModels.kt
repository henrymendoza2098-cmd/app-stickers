package com.example.whatsapp_stickers_app

data class Sticker(
    val imageFileName: String,
    val emojis: List<String>,
    val accessibilityText: String? = null
)

data class StickerPack(
    val identifier: String,
    val name: String,
    val publisher: String,
    val trayImageFile: String,
    val androidPlayStoreLink: String = "",
    val iosAppStoreLink: String = "",
    val publisherEmail: String = "",
    val publisherWebsite: String = "",
    val privacyPolicyWebsite: String = "",
    val licenseAgreementWebsite: String = "",
    val imageDataVersion: String = "1",
    val avoidCache: Boolean = false,
    val animatedStickerPack: Boolean = false,
    val stickers: MutableList<Sticker> = mutableListOf()
)
