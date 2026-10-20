package com.lumiaiq.smartkey

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.Executors

internal object DesktopInstallerValidation {
    private val assetPathPattern =
        Regex("^assets/desktop_installers/releases/(\\d+\\.\\d+\\.\\d+)-[0-9a-f]{12}/([^/]+)$")
    private val windowsFilePattern = Regex("^LumiaKey-Windows-v(\\d+\\.\\d+\\.\\d+)-Setup\\.exe$")
    private val macFilePattern = Regex("^LumiaKey-macOS-v(\\d+\\.\\d+\\.\\d+)\\.dmg$")
    const val maxBytes: Long = 512L * 1024L * 1024L

    fun validateExport(
        assetPath: String,
        fileName: String,
        sizeBytes: Long,
        sha256: String,
    ): String? {
        if (sizeBytes <= 0 || sizeBytes > maxBytes || !sha256.matches(Regex("^[0-9a-f]{64}$"))) {
            return "Invalid installer size or SHA-256."
        }
        if (fileName.isBlank() || fileName.contains('/') || fileName.contains('\\') ||
            fileName == "." || fileName == ".." || fileName.contains('\u0000')
        ) {
            return "Installer filename is invalid."
        }
        val path = assetPathPattern.matchEntire(assetPath) ?: return "Installer asset path is not allowlisted."
        val version = path.groupValues[1]
        val pathName = path.groupValues[2]
        if (pathName != fileName) return "Installer path and filename do not match."
        val windows = windowsFilePattern.matchEntire(fileName)
        val mac = macFilePattern.matchEntire(fileName)
        if ((windows == null || windows.groupValues[1] != version) &&
            (mac == null || mac.groupValues[1] != version)
        ) {
            return "Installer platform filename is not allowlisted for this release."
        }
        return null
    }

    fun validateLocalFolder(authority: String?, documentId: String): String? {
        if (authority != "com.android.externalstorage.documents") {
            return "Choose a folder from local Android shared storage."
        }
        val separator = documentId.indexOf(':')
        if (separator <= 0) return "The selected folder is not on local shared storage."
        val volume = documentId.substring(0, separator)
        val relativePath = documentId.substring(separator + 1)
        if (!volume.matches(Regex("^[A-Za-z0-9_-]+$"))) {
            return "The selected storage volume is invalid."
        }
        val segments = relativePath.split('/').filter { it.isNotEmpty() }
        if (segments.any { it == "." || it == ".." }) {
            return "The selected folder path is invalid."
        }
        if (segments.size >= 2 && segments[0].equals("Android", ignoreCase = true) &&
            (segments[1].equals("data", ignoreCase = true) ||
                segments[1].equals("obb", ignoreCase = true))
        ) {
            return "Android data and OBB folders cannot be used for installer export."
        }
        return null
    }
}

/** Selects a local SAF folder and streams verified APK installer assets into it. */
class DesktopInstallerController(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val preferences = activity.getSharedPreferences(PREFERENCES, Activity.MODE_PRIVATE)
    private var pendingDirectoryResult: MethodChannel.Result? = null
    @Volatile
    private var closed = false
    private val pendingWorkerResults = Collections.synchronizedSet(mutableSetOf<MethodChannel.Result>())
    private val pendingExports = AtomicInteger(0)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "chooseExportDirectory" -> chooseExportDirectory(result)
            "verifyInstaller" -> verifyInstaller(call, result)
            "exportInstaller" -> exportInstaller(call, result)
            else -> result.notImplemented()
        }
    }

    private fun chooseExportDirectory(result: MethodChannel.Result) {
        if (closed) {
            result.error("closed", "Installer export is unavailable.", null)
            return
        }
        if (pendingDirectoryResult != null) {
            result.error("selection_in_progress", "Finish the current folder selection first.", null)
            return
        }
        if (pendingExports.get() > 0) {
            result.error("export_in_progress", "Wait for the current installer export to finish before changing folders.", null)
            return
        }
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                )
            }
            pendingDirectoryResult = result
            activity.startActivityForResult(intent, REQUEST_DIRECTORY)
        } catch (error: Exception) {
            pendingDirectoryResult = null
            result.error("folder_picker_unavailable", error.message, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_DIRECTORY) return false
        val result = pendingDirectoryResult ?: return true
        pendingDirectoryResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return true
        }
        val uri = data?.data
        if (uri == null) {
            result.error("invalid_folder", "Android returned no folder.", null)
            return true
        }
        try {
            val displayName = validateAndGetFolderName(uri)
            val flags = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            activity.contentResolver.takePersistableUriPermission(uri, flags)
            val previousUri = preferences.getString(KEY_TREE_URI, null)?.let(Uri::parse)
            preferences.edit()
                .putString(KEY_TREE_URI, uri.toString())
                .putString(KEY_FOLDER_NAME, displayName)
                .apply()
            if (previousUri != null && previousUri != uri) {
                try {
                    val previousGrant = activity.contentResolver.persistedUriPermissions
                        .firstOrNull { it.uri == previousUri }
                    if (previousGrant != null) {
                        val previousFlags =
                            (if (previousGrant.isReadPermission) Intent.FLAG_GRANT_READ_URI_PERMISSION else 0) or
                                (if (previousGrant.isWritePermission) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0)
                        activity.contentResolver.releasePersistableUriPermission(previousUri, previousFlags)
                    }
                } catch (_: SecurityException) {
                    // The newly selected destination remains valid if Android has already released the old grant.
                }
            }
            result.success(mapOf("treeUri" to uri.toString(), "displayName" to displayName))
        } catch (error: Exception) {
            result.error("invalid_folder", error.message ?: "The selected folder is not supported.", null)
        }
        return true
    }

    private fun validateAndGetFolderName(uri: Uri): String {
        if (uri.scheme != "content" || !DocumentsContract.isTreeUri(uri)) {
            throw IllegalArgumentException("Choose a folder in Android's local file browser.")
        }
        val documentId = DocumentsContract.getTreeDocumentId(uri)
        DesktopInstallerValidation.validateLocalFolder(uri.authority, documentId)?.let {
            throw IllegalArgumentException(it)
        }
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(uri, documentId)
        activity.contentResolver.query(
            documentUri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index) ?: "Selected folder"
            }
        }
        return "Selected folder"
    }

    private fun exportInstaller(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.error("closed", "Installer export is unavailable.", null)
            return
        }
        val treeUri = call.argument<String>("treeUri")?.let(Uri::parse)
        val assetPath = call.argument<String>("assetPath")
        val fileName = call.argument<String>("fileName")
        val sizeBytes = (call.argument<Number>("sizeBytes"))?.toLong()
        val digest = call.argument<String>("sha256")
        if (treeUri == null || assetPath == null || fileName == null ||
            sizeBytes == null || digest == null
        ) {
            result.error("invalid_arguments", "Installer export arguments are incomplete.", null)
            return
        }
        DesktopInstallerValidation.validateExport(assetPath, fileName, sizeBytes, digest)?.let {
            result.error("invalid_installer", it, null)
            return
        }
        val savedUri = preferences.getString(KEY_TREE_URI, null)
        if (savedUri != treeUri.toString()) {
            result.error("unselected_folder", "Choose this export folder in the app first.", null)
            return
        }
        pendingExports.incrementAndGet()
        runWorker(result, "export_failed", onFinished = { pendingExports.decrementAndGet() }) {
            writeVerifiedInstaller(
                treeUri = treeUri,
                assetPath = assetPath,
                fileName = fileName,
                expectedSize = sizeBytes,
                expectedDigest = digest,
            )
        }
    }

    private fun verifyInstaller(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.error("closed", "Installer verification is unavailable.", null)
            return
        }
        val assetPath = call.argument<String>("assetPath")
        val fileName = call.argument<String>("fileName")
        val sizeBytes = call.argument<Number>("sizeBytes")?.toLong()
        val expectedDigest = call.argument<String>("sha256")
        if (assetPath == null || fileName == null || sizeBytes == null || expectedDigest == null) {
            result.error("invalid_arguments", "Installer verification arguments are incomplete.", null)
            return
        }
        DesktopInstallerValidation.validateExport(assetPath, fileName, sizeBytes, expectedDigest)?.let {
            result.error("invalid_installer", it, null)
            return
        }
        runWorker(result, "verification_failed") {
            val bytesWritten = verifyAsset(assetPath, fileName, sizeBytes, expectedDigest)
            mapOf(
                "fileName" to fileName,
                "bytesWritten" to bytesWritten,
                "sha256" to expectedDigest,
            )
        }
    }

    private fun runWorker(
        result: MethodChannel.Result,
        errorCode: String,
        onFinished: () -> Unit = {},
        task: () -> Any,
    ) {
        if (closed) {
            onFinished()
            result.error("closed", "Installer operation was cancelled.", null)
            return
        }
        pendingWorkerResults.add(result)
        try {
            worker.execute {
                try {
                    completeWorkerResult(result, value = task())
                } catch (error: Exception) {
                    completeWorkerResult(result, errorCode = errorCode, error = error)
                } finally {
                    onFinished()
                }
            }
        } catch (error: Exception) {
            completeWorkerResult(result, errorCode = errorCode, error = error)
            onFinished()
        }
    }

    private fun completeWorkerResult(
        result: MethodChannel.Result,
        value: Any? = null,
        errorCode: String? = null,
        error: Exception? = null,
    ) {
        if (!pendingWorkerResults.remove(result)) return
        mainHandler.post {
            if (closed) {
                result.error("activity_closed", "Installer operation was interrupted.", null)
            } else if (error != null) {
                result.error(errorCode ?: "operation_failed", error.message ?: "Installer operation failed.", null)
            } else {
                result.success(value)
            }
        }
    }

    private fun verifyAsset(
        assetPath: String,
        fileName: String,
        expectedSize: Long,
        expectedDigest: String,
    ): Long {
        ensureOpen()
        val lookupKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)
        val digest = MessageDigest.getInstance("SHA-256")
        var count = 0L
        activity.assets.open(lookupKey).use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                ensureOpen()
                val read = input.read(buffer)
                if (read < 0) break
                count += read
                if (count > expectedSize || count > DesktopInstallerValidation.maxBytes) {
                    throw IllegalStateException("$fileName is larger than its catalog size.")
                }
                digest.update(buffer, 0, read)
            }
        }
        val actualDigest = digest.digest().joinToString("") { byte -> "%02x".format(byte) }
        if (count != expectedSize || actualDigest != expectedDigest) {
            throw IllegalStateException("$fileName size or SHA-256 verification failed.")
        }
        return count
    }

    private fun writeVerifiedInstaller(
        treeUri: Uri,
        assetPath: String,
        fileName: String,
        expectedSize: Long,
        expectedDigest: String,
    ): Map<String, Any> {
        ensureOpen()
        val folderName = validateAndGetFolderName(treeUri)
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        val directoryUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
        if (containsChildNamed(treeUri, documentId, fileName)) {
            throw IllegalStateException("$fileName already exists in $folderName; no file was replaced.")
        }
        verifyAsset(assetPath, fileName, expectedSize, expectedDigest)
        var documentUri = DocumentsContract.createDocument(
            activity.contentResolver,
            directoryUri,
            "application/octet-stream",
            fileName,
        ) ?: throw IllegalStateException("Android could not reserve $fileName in the selected folder.")

        try {
            val actualName = queryDisplayName(documentUri)
            if (actualName != fileName) {
                throw IllegalStateException("The selected storage provider changed the requested filename.")
            }
            val lookupKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)
            val digest = MessageDigest.getInstance("SHA-256")
            var count = 0L
            activity.assets.open(lookupKey).use { input ->
                activity.contentResolver.openOutputStream(documentUri, "w")?.use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        ensureOpen()
                        val read = input.read(buffer)
                        if (read < 0) break
                        count += read
                        if (count > expectedSize || count > DesktopInstallerValidation.maxBytes) {
                            throw IllegalStateException("Installer asset is larger than its catalog size.")
                        }
                        digest.update(buffer, 0, read)
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                } ?: throw IllegalStateException("Android could not open the selected folder for writing.")
            }
            val actualDigest = digest.digest().joinToString("") { byte -> "%02x".format(byte) }
            if (count != expectedSize || actualDigest != expectedDigest) {
                throw IllegalStateException("Installer size or SHA-256 verification failed.")
            }
            verifyStoredDocument(documentUri, fileName, expectedSize, expectedDigest)
            ensureOpen()
            return mapOf(
                "fileName" to actualName,
                "documentUri" to documentUri.toString(),
                "bytesWritten" to count,
                "sha256" to actualDigest,
            )
        } catch (error: Exception) {
            try {
                DocumentsContract.deleteDocument(activity.contentResolver, documentUri)
            } catch (_: Exception) {
                // Never delete anything but the document URI created by this operation.
            }
            throw error
        }
    }

    private fun containsChildNamed(treeUri: Uri, documentId: String, fileName: String): Boolean {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
        val cursor = activity.contentResolver.query(
            childrenUri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        ) ?: throw IllegalStateException("Android could not list the selected export folder safely.")
        cursor.use {
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index < 0) throw IllegalStateException("Android did not return folder filenames.")
            while (cursor.moveToNext()) {
                if (cursor.getString(index)?.equals(fileName, ignoreCase = true) == true) return true
            }
        }
        return false
    }

    private fun verifyStoredDocument(
        uri: Uri,
        fileName: String,
        expectedSize: Long,
        expectedDigest: String,
    ) {
        val actualDigest = MessageDigest.getInstance("SHA-256")
        var count = 0L
        val input = activity.contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("Android could not reopen the exported installer document.")
        input.use {
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                ensureOpen()
                val read = input.read(buffer)
                if (read < 0) break
                count += read
                if (count > expectedSize || count > DesktopInstallerValidation.maxBytes) {
                    throw IllegalStateException("Stored $fileName is larger than its catalog size.")
                }
                actualDigest.update(buffer, 0, read)
            }
        }
        val digestHex = actualDigest.digest().joinToString("") { byte -> "%02x".format(byte) }
        if (count != expectedSize || digestHex != expectedDigest) {
            throw IllegalStateException("Stored $fileName failed size or SHA-256 verification.")
        }
    }

    private fun ensureOpen() {
        if (closed || Thread.currentThread().isInterrupted) {
            throw IllegalStateException("Installer operation was cancelled.")
        }
    }

    private fun queryDisplayName(uri: Uri): String {
        activity.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index).orEmpty()
            }
        }
        return ""
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        pendingDirectoryResult?.error("activity_closed", "Folder selection was interrupted.", null)
        pendingDirectoryResult = null
        val pending = synchronized(pendingWorkerResults) {
            pendingWorkerResults.toList().also { pendingWorkerResults.clear() }
        }
        pending.forEach { result ->
            result.error("activity_closed", "Installer operation was interrupted.", null)
        }
        worker.shutdownNow()
    }

    companion object {
        private const val CHANNEL_NAME = "smart_keys/desktop_installers"
        private const val REQUEST_DIRECTORY = 0x4D31
        private const val PREFERENCES = "desktop_installer_export"
        private const val KEY_TREE_URI = "tree_uri"
        private const val KEY_FOLDER_NAME = "folder_name"
    }
}
