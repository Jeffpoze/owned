package com.jeffpoze.owned.textreader

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * On-device vision with Google ML Kit: reads printed text from an image file, and cuts
 * the main subject out of a photo onto a clean white background.
 */
class TextReaderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "owned/text_reader")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "liftSubject") return liftSubject(call, result)
        if (call.method != "recognize") return result.notImplemented()
        val path = call.argument<String>("path") ?: return result.error("bad_image", "No image path.", null)
        val image = try {
            InputImage.fromFilePath(context, Uri.fromFile(File(path)))
        } catch (e: Exception) {
            return result.error("bad_image", "Couldn't open the image.", null)
        }
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        recognizer.process(image)
            .addOnSuccessListener { text ->
                // Join pieces on the same printed row (a receipt's item and its price), top to bottom.
                val pieces = text.textBlocks.flatMap { it.lines }.filter { it.boundingBox != null }
                    .sortedBy { it.boundingBox!!.centerY() }
                val rows = mutableListOf<MutableList<com.google.mlkit.vision.text.Text.Line>>()
                for (p in pieces) {
                    val last = rows.lastOrNull()?.last()
                    val box = p.boundingBox!!
                    if (last != null && Math.abs(last.boundingBox!!.centerY() - box.centerY()) <
                        Math.min(last.boundingBox!!.height(), box.height()) / 2) {
                        rows.last().add(p)
                    } else {
                        rows.add(mutableListOf(p))
                    }
                }
                val lines = rows.map { row -> row.sortedBy { it.boundingBox!!.left }.joinToString("  ") { it.text } }
                result.success(lines.joinToString("\n"))
            }
            .addOnFailureListener { e -> result.error("recognition_failed", e.message, null) }
            .addOnCompleteListener { recognizer.close() }
    }

    /**
     * Cuts the photo's subject out and centres it on a white square, saved as a JPEG in the
     * cache folder. Returns its path, or null when nothing stands out or the segmentation
     * model isn't available yet (Google Play services downloads it on first use).
     */
    private fun liftSubject(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: return result.error("bad_image", "No image path.", null)
        val image = try {
            InputImage.fromFilePath(context, Uri.fromFile(File(path)))
        } catch (e: Exception) {
            return result.error("bad_image", "Couldn't open the image.", null)
        }
        val segmenter = SubjectSegmentation.getClient(
            SubjectSegmenterOptions.Builder().enableForegroundBitmap().build()
        )
        segmenter.process(image)
            .addOnSuccessListener { r ->
                val fg = r.foregroundBitmap
                if (fg == null) {
                    result.success(null)
                    return@addOnSuccessListener
                }
                val cut = cropToContent(fg) ?: run {
                    result.success(null)
                    return@addOnSuccessListener
                }
                // White square with a margin, subject centred: reads like a catalog photo.
                val side = (maxOf(cut.width, cut.height) * 1.15f).toInt()
                val out = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
                Canvas(out).apply {
                    drawColor(Color.WHITE)
                    drawBitmap(cut, ((side - cut.width) / 2).toFloat(), ((side - cut.height) / 2).toFloat(), null)
                }
                val file = File(context.cacheDir, "lifted_${System.currentTimeMillis()}.jpg")
                file.outputStream().use { out.compress(Bitmap.CompressFormat.JPEG, 90, it) }
                result.success(file.absolutePath)
            }
            .addOnFailureListener { result.success(null) }
            .addOnCompleteListener { segmenter.close() }
    }

    /** The smallest part of the bitmap that isn't transparent, or null if it's all transparent. */
    private fun cropToContent(b: Bitmap): Bitmap? {
        val w = b.width
        val h = b.height
        val px = IntArray(w * h)
        b.getPixels(px, 0, w, 0, 0, w, h)
        var minX = w
        var minY = h
        var maxX = -1
        var maxY = -1
        for (y in 0 until h) {
            for (x in 0 until w) {
                if ((px[y * w + x] ushr 24) > 16) {
                    if (x < minX) minX = x
                    if (x > maxX) maxX = x
                    if (y < minY) minY = y
                    if (y > maxY) maxY = y
                }
            }
        }
        if (maxX < minX || maxY < minY) return null
        return Bitmap.createBitmap(b, minX, minY, maxX - minX + 1, maxY - minY + 1)
    }
}
