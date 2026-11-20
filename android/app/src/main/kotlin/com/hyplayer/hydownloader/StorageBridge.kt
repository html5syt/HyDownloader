package com.hyplayer.hydownloader

import android.app.Activity
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.util.Base64
import android.webkit.MimeTypeMap
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.Executors

/** 持久化系统目录授权，使用 ContentResolver 流式读写，支持 SD 卡和 U 盘。 */
class StorageBridge(private val activity: Activity, channel: MethodChannel) {
    private val executor = Executors.newFixedThreadPool(2)
    private var pickerResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "sdkVersion" -> result.success(Build.VERSION.SDK_INT)
                "pickDirectory" -> pickDirectory(result)
                else -> executor.execute {
                    try {
                        val value = handle(call)
                        activity.runOnUiThread { result.success(value) }
                    } catch (e: Exception) {
                        activity.runOnUiThread {
                            result.error("storage_access", "无法访问此文件夹，请重新选择并允许访问", e.message)
                        }
                    }
                }
            }
        }
    }

    private fun pickDirectory(result: MethodChannel.Result) {
        if (pickerResult != null) {
            result.error("picker_busy", "请先完成当前文件夹选择", null)
            return
        }
        pickerResult = result
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }, REQUEST_DIRECTORY)
        } catch (e: Exception) {
            pickerResult = null
            result.error("picker_unavailable", "此设备无法选择文件夹", e.message)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_DIRECTORY) return false
        val result = pickerResult ?: return true
        pickerResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        executor.execute {
            try {
                require(flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0)
                require(flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
                activity.contentResolver.takePersistableUriPermission(uri, flags)
                val root = DocumentFile.fromTreeUri(activity, uri) ?: error("Invalid tree")
                require(root.isDirectory && root.canRead() && root.canWrite())
                // 实际创建并删除测试文件，不能仅凭权限位宣称可写。
                val probe = root.createFile("application/octet-stream", ".hydownloader-${System.nanoTime()}")
                    ?: error("Directory is not writable")
                try {
                    activity.contentResolver.openOutputStream(probe.uri, "wt")!!.use { it.write(0) }
                } finally {
                    check(probe.delete())
                }
                activity.runOnUiThread { result.success(mapOf("uri" to uri.toString(), "name" to (root.name ?: "音乐文件夹"))) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("storage_access", "无法写入此文件夹，请选择其他位置", e.message) }
            }
        }
        return true
    }

    /** saf:base64(treeUri)/显示名/文件名；显示名不参与目录解析。 */
    private fun document(path: String, create: Boolean = false): DocumentFile? {
        val parts = path.removePrefix("saf:").split('/')
        require(parts.size >= 2)
        val uri = Uri.parse(String(Base64.decode(parts.first(), Base64.URL_SAFE), Charsets.UTF_8))
        val permission = activity.contentResolver.persistedUriPermissions.firstOrNull { it.uri == uri }
        require(permission != null && permission.isReadPermission && permission.isWritePermission)
        var current = DocumentFile.fromTreeUri(activity, uri) ?: error("Invalid tree")
        require(current.exists() && current.isDirectory && current.canRead())
        for ((index, encoded) in parts.drop(2).withIndex()) {
            val name = Uri.decode(encoded)
            require(name.isNotEmpty() && name != "." && name != ".." && !name.contains('/'))
            val found = current.findFile(name)
            current = found ?: if (create) {
                if (index == parts.size - 3) current.createFile(mimeType(name), name)
                    ?: error("Cannot create file")
                else current.createDirectory(name) ?: error("Cannot create directory")
            } else return null
        }
        return current
    }

    private fun mimeType(name: String): String = MimeTypeMap.getSingleton()
        .getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase()) ?: "application/octet-stream"

    private fun input(path: String): InputStream = if (path.startsWith("saf:")) {
        activity.contentResolver.openInputStream(document(path)?.uri ?: error("Missing file"))
            ?: error("Cannot read file")
    } else File(path).inputStream()

    private fun output(path: String): OutputStream = if (path.startsWith("saf:")) {
        activity.contentResolver.openOutputStream(document(path, true)!!.uri, "wt")
            ?: error("Cannot write file")
    } else File(path).outputStream()

    private fun handle(call: MethodCall): Any? {
        val path = call.argument<String>("path") ?: ""
        return when (call.method) {
            "checkDirectory" -> {
                val root = document(path) ?: error("Missing directory")
                require(root.isDirectory && root.canRead() && root.canWrite())
                null
            }
            "listFiles" -> {
                val root = document(path) ?: error("Missing directory")
                require(root.isDirectory && root.canRead())
                // 查询失败不能当成空目录。DocumentFile.listFiles 本身会吞掉查询异常。
                val childrenUri = android.provider.DocumentsContract.buildChildDocumentsUriUsingTree(
                    root.uri, android.provider.DocumentsContract.getDocumentId(root.uri))
                val names = mutableListOf<String>()
                activity.contentResolver.query(childrenUri, arrayOf(
                    android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    android.provider.DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)
                    ?.use { cursor ->
                        while (cursor.moveToNext()) {
                            if (cursor.getString(1) != android.provider.DocumentsContract.Document.MIME_TYPE_DIR)
                                names.add(cursor.getString(0))
                        }
                    } ?: error("Cannot list directory")
                names
            }
            "exists" -> document(path)?.exists() ?: false
            "length" -> document(path)?.length() ?: error("Missing file")
            "delete" -> { document(path)?.let { check(it.delete()) }; null }
            "writeText" -> { output(path).use { it.write(call.argument<String>("text")!!.toByteArray(Charsets.UTF_8)) }; null }
            "copy" -> {
                val source = call.argument<String>("source")!!
                val destination = call.argument<String>("destination")!!
                require(source != destination)
                input(source).use { sourceStream -> output(destination).use { sourceStream.copyTo(it) } }
                null
            }
            "audioDuration" -> {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(path)
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                } finally { retriever.release() }
            }
            else -> error("Unknown storage operation")
        }
    }

    fun close() { executor.shutdown() }

    companion object { const val REQUEST_DIRECTORY = 4601 }
}
