package com.example.whatsapp_stickers_app

import android.content.ContentProvider
import android.content.ContentValues
import android.content.UriMatcher
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.text.TextUtils
import java.io.IOException

/**
 * Versión actualizada: ahora sirve tanto el pack de demo empaquetado en
 * assets como los packs dinámicos creados por el usuario en tiempo de
 * ejecución (vía StickerPackRepository). No cambies los nombres de
 * columnas ni la estructura de las URIs: son parte del contrato que
 * WhatsApp espera.
 */
class StickerPackContentProvider : ContentProvider() {

    companion object {
        const val STICKER_PACK_IDENTIFIER_IN_QUERY = "sticker_pack_identifier"
        const val STICKER_PACK_NAME_IN_QUERY = "sticker_pack_name"
        const val STICKER_PACK_PUBLISHER_IN_QUERY = "sticker_pack_publisher"
        const val STICKER_PACK_ICON_IN_QUERY = "sticker_pack_icon"
        const val ANDROID_APP_DOWNLOAD_LINK_IN_QUERY = "android_play_store_link"
        const val IOS_APP_DOWNLOAD_LINK_IN_QUERY = "ios_app_download_link"
        const val PUBLISHER_EMAIL = "sticker_pack_publisher_email"
        const val PUBLISHER_WEBSITE = "sticker_pack_publisher_website"
        const val PRIVACY_POLICY_WEBSITE = "sticker_pack_privacy_policy_website"
        const val LICENSE_AGREEMENT_WEBSITE = "sticker_pack_license_agreement_website"
        const val IMAGE_DATA_VERSION = "image_data_version"
        const val AVOID_CACHE = "whatsapp_will_not_cache_stickers"
        const val ANIMATED_STICKER_PACK = "animated_sticker_pack"
        const val STICKER_FILE_NAME_IN_QUERY = "sticker_file_name"
        const val STICKER_FILE_EMOJI_IN_QUERY = "sticker_emoji"
        const val STICKER_FILE_ACCESSIBILITY_TEXT_IN_QUERY = "sticker_accessibility_text"

        const val METADATA = "metadata"
        const val STICKERS = "stickers"
        const val STICKERS_ASSET = "stickers_asset"

        private const val METADATA_CODE = 1
        private const val METADATA_CODE_FOR_SINGLE_PACK = 2
        private const val STICKERS_CODE = 3
        private const val STICKERS_ASSET_CODE = 4

        private val MATCHER = UriMatcher(UriMatcher.NO_MATCH)
    }

    private var authority: String = ""

    override fun onCreate(): Boolean {
        val ctx = context ?: return false
        authority = "${ctx.packageName}.stickercontentprovider"

        MATCHER.addURI(authority, METADATA, METADATA_CODE)
        MATCHER.addURI(authority, "$METADATA/*", METADATA_CODE_FOR_SINGLE_PACK)
        MATCHER.addURI(authority, "$STICKERS/*", STICKERS_CODE)
        // Wildcard: como los packs son dinámicos, no los enumeramos aquí;
        // se validan en el momento de la consulta contra el repositorio.
        MATCHER.addURI(authority, "$STICKERS_ASSET/*/*", STICKERS_ASSET_CODE)
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        return when (MATCHER.match(uri)) {
            METADATA_CODE -> getPackInfo(uri, StickerPackRepository.getAllPacks(context!!))
            METADATA_CODE_FOR_SINGLE_PACK -> {
                val identifier = uri.lastPathSegment
                getPackInfo(
                    uri,
                    StickerPackRepository.getAllPacks(context!!).filter { it.identifier == identifier }
                )
            }
            STICKERS_CODE -> getStickersForPack(uri)
            else -> throw IllegalArgumentException("Unknown URI: $uri")
        }
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? {
        return when (MATCHER.match(uri)) {
            STICKERS_ASSET_CODE -> getImageAsset(uri)
            else -> null
        }
    }

    override fun getType(uri: Uri): String {
        return when (MATCHER.match(uri)) {
            METADATA_CODE -> "vnd.android.cursor.dir/vnd.$authority.$METADATA"
            METADATA_CODE_FOR_SINGLE_PACK -> "vnd.android.cursor.item/vnd.$authority.$METADATA"
            STICKERS_CODE -> "vnd.android.cursor.dir/vnd.$authority.$STICKERS"
            STICKERS_ASSET_CODE -> {
                val fileName = uri.lastPathSegment ?: ""
                if (fileName.endsWith(".png")) "image/png" else "image/webp"
            }
            else -> throw IllegalArgumentException("Unknown URI: $uri")
        }
    }

    private fun getPackInfo(uri: Uri, packs: List<StickerPack>): Cursor {
        val cursor = MatrixCursor(
            arrayOf(
                STICKER_PACK_IDENTIFIER_IN_QUERY, STICKER_PACK_NAME_IN_QUERY, STICKER_PACK_PUBLISHER_IN_QUERY,
                STICKER_PACK_ICON_IN_QUERY, ANDROID_APP_DOWNLOAD_LINK_IN_QUERY, IOS_APP_DOWNLOAD_LINK_IN_QUERY,
                PUBLISHER_EMAIL, PUBLISHER_WEBSITE, PRIVACY_POLICY_WEBSITE, LICENSE_AGREEMENT_WEBSITE,
                IMAGE_DATA_VERSION, AVOID_CACHE, ANIMATED_STICKER_PACK
            )
        )
        for (pack in packs) {
            cursor.newRow()
                .add(pack.identifier).add(pack.name).add(pack.publisher)
                .add(pack.trayImageFile).add(pack.androidPlayStoreLink).add(pack.iosAppStoreLink)
                .add(pack.publisherEmail).add(pack.publisherWebsite).add(pack.privacyPolicyWebsite)
                .add(pack.licenseAgreementWebsite).add(pack.imageDataVersion)
                .add(if (pack.avoidCache) 1 else 0).add(if (pack.animatedStickerPack) 1 else 0)
        }
        cursor.setNotificationUri(context!!.contentResolver, uri)
        return cursor
    }

    private fun getStickersForPack(uri: Uri): Cursor {
        val identifier = uri.lastPathSegment
        val cursor = MatrixCursor(
            arrayOf(STICKER_FILE_NAME_IN_QUERY, STICKER_FILE_EMOJI_IN_QUERY, STICKER_FILE_ACCESSIBILITY_TEXT_IN_QUERY)
        )
        for (pack in StickerPackRepository.getAllPacks(context!!)) {
            if (pack.identifier == identifier) {
                for (sticker in pack.stickers) {
                    cursor.newRow()
                        .add(sticker.imageFileName)
                        .add(TextUtils.join(",", sticker.emojis))
                        .add(sticker.accessibilityText ?: "")
                }
            }
        }
        cursor.setNotificationUri(context!!.contentResolver, uri)
        return cursor
    }

    private fun getImageAsset(uri: Uri): AssetFileDescriptor? {
        val segments = uri.pathSegments
        if (segments.size != 3) {
            throw IllegalArgumentException("path segments should be 3, uri is: $uri")
        }
        val fileName = segments[2]
        val identifier = segments[1]
        if (TextUtils.isEmpty(identifier) || TextUtils.isEmpty(fileName)) {
            throw IllegalArgumentException("identifier or file name empty, uri: $uri")
        }

        val pack = StickerPackRepository.getAllPacks(context!!).find { it.identifier == identifier }
            ?: return null
        val isValidFile = fileName == pack.trayImageFile || pack.stickers.any { it.imageFileName == fileName }
        if (!isValidFile) return null

        return try {
            if (identifier == StickerPackRepository.BUNDLED_DEMO_IDENTIFIER) {
                context!!.assets.openFd("$identifier/$fileName")
            } else {
                val file = StickerPackRepository.fileFor(context!!, identifier, fileName)
                val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                AssetFileDescriptor(pfd, 0, file.length())
            }
        } catch (e: IOException) {
            null
        }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri {
        throw UnsupportedOperationException("Not supported")
    }

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int {
        throw UnsupportedOperationException("Not supported")
    }

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int {
        throw UnsupportedOperationException("Not supported")
    }
}
