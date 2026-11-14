package org.foss.youtube.next

import android.annotation.SuppressLint
import android.content.Context
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.node.ArrayNode
import java.io.File
import java.io.IOException
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.apache.commons.io.FileUtils
import org.foss.youtube.common.prefs.SharedPrefsHelper
import org.foss.youtube.common.prefs.SharedPrefsHelper.update
import org.foss.youtube.next.YoutubeDL.getInstance

internal object YoutubeDLUpdater {
    private const val dlpBinaryName = "yt-dlp"
    private const val dlpVersionKey = "dlpVersion"
    private const val dlpVersionNameKey = "dlpVersionName"

    internal suspend fun update(
        appContext: Context?,
        youtubeDLChannel: YoutubeDL.UpdateChannel = YoutubeDL.UpdateChannel.Stable
    ): YoutubeDL.UpdateStatus {
        val json = checkForUpdate(appContext!!, youtubeDLChannel)
            ?: return YoutubeDL.UpdateStatus.AlreadyUpToDate
        val downloadUrl = getDownloadUrl(json)
        val file = download(appContext, downloadUrl)
        val ytdlpDir = getYoutubeDLDir(
            appContext
        )
        val binary = File(ytdlpDir, dlpBinaryName)
        try {
            /* purge older version */
            if (ytdlpDir.exists()) FileUtils.deleteDirectory(ytdlpDir)
            /* install newer version */
            ytdlpDir.mkdirs()
            FileUtils.copyFile(file, binary)
        } catch (e: Exception) {
            /* if something went wrong restore default version */
            FileUtils.deleteQuietly(ytdlpDir)
            getInstance().initYtdlp(appContext, ytdlpDir)
            throw YoutubeDLException(e)
        } finally {
            file.delete()
        }
        updateSharedPrefs(appContext, getTag(json), getName(json))
        return YoutubeDL.UpdateStatus.Done
    }

    private fun updateSharedPrefs(appContext: Context, tag: String, name: String) {
        update(appContext, dlpVersionKey, tag)
        update(appContext, dlpVersionNameKey, name)
    }

    @SuppressLint("SuspiciousIndentation")
    private suspend fun checkForUpdate(appContext: Context, youtubeDLChannel: YoutubeDL.UpdateChannel): JsonNode? =
        withContext(Dispatchers.IO) {
            val url = URL(youtubeDLChannel.apiUrl)
            val json: JsonNode = url.openStream().use { YoutubeDL.objectMapper.readTree(it) }
            val newVersion = getTag(json)
            val oldVersion = SharedPrefsHelper[appContext, dlpVersionKey]
            return@withContext if (newVersion == oldVersion) {
                null
            } else {
                json
            }
        }

    private fun getTag(json: JsonNode): String = json["tag_name"].asText()

    private fun getName(json: JsonNode): String = json["name"].asText()

    private suspend fun getDownloadUrl(json: JsonNode): String = withContext(Dispatchers.IO) {
        val assets = json["assets"] as? ArrayNode
            ?: throw YoutubeDLException(
                IOException("Release response does not contain an assets array")
            )
        return@withContext assets.firstOrNull {
            it["name"].asText() == YoutubeDL.ytdlpBin
        }
            ?.get("browser_download_url")
            ?.asText()
            ?: throw YoutubeDLException(IOException("Could not find download URL for ${YoutubeDL.ytdlpBin}"))
    }

    private suspend fun download(appContext: Context, url: String): File = withContext(Dispatchers.IO) {
        val downloadUrl = URL(url)
        val file = File.createTempFile(
            dlpBinaryName,
            null,
            appContext.cacheDir
        )
        var completed = false
        try {
            FileUtils.copyURLToFile(
                downloadUrl,
                file,
                5000,
                10000
            )
            completed = true
            file
        } finally {
            if (!completed) {
                file.delete()
            }
        }
    }

    private fun getYoutubeDLDir(appContext: Context): File {
        val baseDir = File(appContext.noBackupFilesDir, YoutubeDL.baseName)
        return File(baseDir, YoutubeDL.ytdlpDirName)
    }

    fun version(appContext: Context?): String? = SharedPrefsHelper[appContext!!, dlpVersionKey]

    fun versionName(appContext: Context?): String? = SharedPrefsHelper[appContext!!, dlpVersionNameKey]
}
