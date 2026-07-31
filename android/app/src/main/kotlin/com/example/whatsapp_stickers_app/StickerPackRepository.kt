package com.example.whatsapp_stickers_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/**
 * Maneja el almacenamiento de los packs creados dinámicamente por el
 * usuario (en el almacenamiento interno privado de la app), y los
 * combina con el pack de demostración que viene empaquetado en assets
 * (el que ya funcionaba: "pack_prueba_01").
 */
object StickerPackRepository {

    private const val INDEX_FILE_NAME = "sticker_packs_index.json"
    private const val PACKS_DIR_NAME = "sticker_packs"
    const val BUNDLED_DEMO_IDENTIFIER = "pack_prueba_01"

    private fun packsDir(context: Context): File {
        val dir = File(context.filesDir, PACKS_DIR_NAME)
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun indexFile(context: Context): File = File(context.filesDir, INDEX_FILE_NAME)

    private fun loadDynamicIndex(context: Context): JSONArray {
        val file = indexFile(context)
        if (!file.exists()) return JSONArray()
        val text = file.readText()
        if (text.isBlank()) return JSONArray()
        return JSONArray(text)
    }

    private fun saveDynamicIndex(context: Context, array: JSONArray) {
        indexFile(context).writeText(array.toString())
    }

    /** Devuelve TODOS los packs: el de demo (assets) + los creados por el usuario */
    fun getAllPacks(context: Context): List<StickerPack> {
        val packs = mutableListOf<StickerPack>()

        try {
            packs.addAll(ContentFileParser.parseStickerPacks(context))
        } catch (e: Exception) {
            // Si no existe contents.json en assets, simplemente lo omitimos
        }

        val dynamicArray = loadDynamicIndex(context)
        for (i in 0 until dynamicArray.length()) {
            val p = dynamicArray.getJSONObject(i)
            val pack = StickerPack(
                identifier = p.getString("identifier"),
                name = p.getString("name"),
                publisher = p.getString("publisher"),
                trayImageFile = p.getString("tray_image_file"),
                imageDataVersion = p.optString("image_data_version", "1")
            )
            val stickersArray = p.getJSONArray("stickers")
            for (j in 0 until stickersArray.length()) {
                val s = stickersArray.getJSONObject(j)
                val emojisArray = s.optJSONArray("emojis")
                val emojis = mutableListOf<String>()
                if (emojisArray != null) {
                    for (k in 0 until emojisArray.length()) emojis.add(emojisArray.getString(k))
                }
                pack.stickers.add(Sticker(s.getString("image_file"), emojis))
            }
            packs.add(pack)
        }
        return packs
    }

    fun isDynamicPack(identifier: String): Boolean = identifier != BUNDLED_DEMO_IDENTIFIER

    /** Ruta física de un sticker/tray de un pack dinámico */
    fun fileFor(context: Context, identifier: String, fileName: String): File {
        return File(File(packsDir(context), identifier), fileName)
    }

    /** Bytes del tray icon, tanto del pack de demo (assets) como de uno dinámico */
    fun trayBytes(context: Context, identifier: String): ByteArray? {
        return try {
            if (identifier == BUNDLED_DEMO_IDENTIFIER) {
                context.assets.open("$identifier/tray.png").use { it.readBytes() }
            } else {
                fileFor(context, identifier, "tray.png").readBytes()
            }
        } catch (e: Exception) {
            null
        }
    }

    /** Bytes de todos los stickers de un pack dinámico */
    fun stickerBytesForPack(context: Context, identifier: String): List<ByteArray>? {
        val pack = getAllPacks(context).find { it.identifier == identifier && isDynamicPack(it.identifier) }
            ?: return null

        return try {
            pack.stickers.map { sticker ->
                fileFor(context, identifier, sticker.imageFileName).readBytes()
            }
        } catch (e: Exception) {
            // Si algún archivo no se puede leer, es mejor no devolver nada
            // para evitar un pack inconsistente en la UI.
            null
        }
    }

    /**
     * Bytes de los primeros N stickers de un pack dinámico.
     * Más eficiente que `stickerBytesForPack` para vistas previas.
     */
    fun firstNStickerBytesForPack(context: Context, identifier: String, count: Int): List<ByteArray>? {
        val pack = getAllPacks(context).find { it.identifier == identifier && isDynamicPack(it.identifier) }
            ?: return null

        return try {
            pack.stickers.take(count).map { sticker ->
                fileFor(context, identifier, sticker.imageFileName).readBytes()
            }
        } catch (e: Exception) {
            // Si algún archivo no se puede leer, es mejor no devolver nada.
            null
        }
    }

    /**
     * Añade un único sticker a un pack ya existente.
     * Es más eficiente que `savePack` porque no necesita reprocesar todos los stickers.
     */
    fun addStickerToPack(
        context: Context,
        identifier: String,
        stickerPng: ByteArray,
        emojis: List<String>
    ) {
        val index = loadDynamicIndex(context)
        var packJson: JSONObject? = null
        for (i in 0 until index.length()) {
            val p = index.getJSONObject(i)
            if (p.getString("identifier") == identifier) {
                packJson = p
                break
            }
        }
        if (packJson == null) throw IllegalArgumentException("Pack con identifier $identifier no encontrado.")

        val stickersArray = packJson.getJSONArray("stickers")
        val newStickerIndex = stickersArray.length()
        val fileName = "sticker_${newStickerIndex + 1}.webp"

        // Guardar el nuevo sticker como archivo .webp
        val bitmap = BitmapFactory.decodeByteArray(stickerPng, 0, stickerPng.size)
        val resized = Bitmap.createScaledBitmap(bitmap, 512, 512, true)
        FileOutputStream(fileFor(context, identifier, fileName)).use { out ->
            @Suppress("DEPRECATION")
            resized.compress(Bitmap.CompressFormat.WEBP, 90, out)
        }

        // Añadir la entrada al JSON y guardar el índice
        stickersArray.put(JSONObject().put("image_file", fileName).put("emojis", JSONArray(emojis)))
        saveDynamicIndex(context, index)
    }

    /**
     * Crea (o reemplaza) un pack dinámico. trayPng y cada sticker en
     * stickersPng vienen como bytes PNG (capturados desde Flutter), y
     * aquí los redimensionamos y comprimimos al formato que exige
     * WhatsApp (tray: PNG 96x96, stickers: WebP 512x512).
     */
    fun savePack(
        context: Context,
        identifier: String,
        name: String,
        publisher: String,
        trayPng: ByteArray,
        stickersPng: List<Pair<ByteArray, List<String>>>
    ) {
        val packDir = File(packsDir(context), identifier)
        if (!packDir.exists()) packDir.mkdirs()

        val trayBitmap = BitmapFactory.decodeByteArray(trayPng, 0, trayPng.size)
        val trayResized = Bitmap.createScaledBitmap(trayBitmap, 96, 96, true)
        FileOutputStream(File(packDir, "tray.png")).use { out ->
            trayResized.compress(Bitmap.CompressFormat.PNG, 100, out)
        }

        val stickerEntries = JSONArray()
        stickersPng.forEachIndexed { index, (bytes, emojis) ->
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            val resized = Bitmap.createScaledBitmap(bitmap, 512, 512, true)
            val fileName = "sticker_${index + 1}.webp"
            FileOutputStream(File(packDir, fileName)).use { out ->
                @Suppress("DEPRECATION")
                resized.compress(Bitmap.CompressFormat.WEBP, 90, out)
            }
            val stickerJson = JSONObject()
            stickerJson.put("image_file", fileName)
            stickerJson.put("emojis", JSONArray(emojis))
            stickerEntries.put(stickerJson)
        }

        val index = loadDynamicIndex(context)
        val newIndex = JSONArray()
        for (i in 0 until index.length()) {
            val p = index.getJSONObject(i)
            if (p.getString("identifier") != identifier) newIndex.put(p)
        }
        val packJson = JSONObject()
        packJson.put("identifier", identifier)
        packJson.put("name", name)
        packJson.put("publisher", publisher)
        packJson.put("tray_image_file", "tray.png")
        packJson.put("image_data_version", "1")
        packJson.put("stickers", stickerEntries)
        newIndex.put(packJson)
        saveDynamicIndex(context, newIndex)
    }

    fun deletePack(context: Context, identifier: String) {
        if (!isDynamicPack(identifier)) return // el pack de demo no se puede borrar
        val index = loadDynamicIndex(context)
        val newIndex = JSONArray()
        for (i in 0 until index.length()) {
            val p = index.getJSONObject(i)
            if (p.getString("identifier") != identifier) newIndex.put(p)
        }
        saveDynamicIndex(context, newIndex)
        File(packsDir(context), identifier).deleteRecursively()
    }

    /** Serializa la lista de packs a JSON para mandarla a Flutter */
    fun packsToJson(context: Context): String {
        val array = JSONArray()
        for (pack in getAllPacks(context)) {
            val obj = JSONObject()
            obj.put("identifier", pack.identifier)
            obj.put("name", pack.name)
            obj.put("publisher", pack.publisher)
            obj.put("stickerCount", pack.stickers.size)
            obj.put("isDynamic", isDynamicPack(pack.identifier))
            array.put(obj)
        }
        return array.toString()
    }
}
