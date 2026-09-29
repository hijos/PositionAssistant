package com.positionassistant.position_assistant

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.InputStreamReader
import java.io.OutputStreamWriter

private const val FILE_PICKER_CHANNEL = "position_assistant/file_picker"
private const val PICK_JSON_REQUEST = 4101
private const val SAVE_JSON_REQUEST = 4102

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingWriteSource: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_PICKER_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "pickJsonFile" && call.method != "saveJsonFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("busy", "已有文件选择请求", null)
                    return@setMethodCallHandler
                }
                if (call.method == "saveJsonFile") {
                    val source = call.argument<String>("source")
                    if (source == null) {
                        result.error("invalid", "缺少导出内容", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    pendingWriteSource = source
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, "position-assistant-export.json")
                    }
                    startActivityForResult(intent, SAVE_JSON_REQUEST)
                    return@setMethodCallHandler
                }
                pendingResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/json"
                }
                startActivityForResult(intent, PICK_JSON_REQUEST)
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_JSON_REQUEST && requestCode != SAVE_JSON_REQUEST) return
        val result = pendingResult
        pendingResult = null
        if (result == null || resultCode != Activity.RESULT_OK || data?.data == null) {
            if (requestCode == SAVE_JSON_REQUEST) pendingWriteSource = null
            result?.success(null)
            return
        }
        try {
            if (requestCode == SAVE_JSON_REQUEST) {
                val source = requireNotNull(pendingWriteSource)
                contentResolver.openOutputStream(data.data!!).use { output ->
                    requireNotNull(output)
                    OutputStreamWriter(output, Charsets.UTF_8).use { writer -> writer.write(source) }
                }
                pendingWriteSource = null
                result.success(true)
                return
            }
            val source = contentResolver.openInputStream(data.data!!).use { input ->
                requireNotNull(input)
                InputStreamReader(input, Charsets.UTF_8).readText()
            }
            result.success(source)
        } catch (error: Exception) {
            result.error("read_failed", "无法读取所选文件", error.message)
        }
    }
}
