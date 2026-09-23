package com.jeffpoze.owned.textreader

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Reads printed text from an image file with Google ML Kit, on the device. */
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
}
