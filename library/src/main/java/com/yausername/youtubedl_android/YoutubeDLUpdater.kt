package com.yausername.youtubedl_android

import android.content.Context
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.node.ArrayNode
import com.yausername.youtubedl_android.YoutubeDL.UpdateChannel
import com.yausername.youtubedl_android.YoutubeDL.UpdateStatus
import com.yausername.youtubedl_android.YoutubeDL.getInstance
import com.yausername.youtubedl_common.SharedPrefsHelper
import com.yausername.youtubedl_common.SharedPrefsHelper.update
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.apache.commons.io.FileUtils
import java.io.File
import java.io.IOException
import java.net.URL

internal object YoutubeDLUpdater {
    private const val dlpBinaryName = "yt-dlp"
    private const val dlpVersionKey = "dlpVersion"
    private const val dlpVersionNameKey = "dlpVersionName"

    internal suspend fun update(
        appContext: Context?,
        youtubeDLChannel: UpdateChannel = UpdateChannel.Stable
    ): UpdateStatus {
        val json = checkForUpdate(appContext!!, youtubeDLChannel)
            ?: return UpdateStatus.ALREADY_UP_TO_DATE
        val downloadUrl = getDownloadUrl(json)
        val file = download(appContext, downloadUrl)
        val ytdlpDir = getYoutubeDLDir(
            appContext
        )
        val binary = File(ytdlpDir, dlpBinaryName)
        try {
            /* purge older version */
            if (ytdlpDir.exists()) FileUtils.deleteDirectory(ytdlpDir)
            /* install newer version */ytdlpDir.mkdirs()
            FileUtils.copyFile(file, binary)
        } catch (e: Exception) {
            /* if something went wrong restore default version */
            FileUtils.deleteQuietly(ytdlpDir)
            getInstance().init_ytdlp(appContext, ytdlpDir)
            throw YoutubeDLException(e)
        } finally {
            file.delete()
        }
        updateSharedPrefs(appContext, getTag(json), getName(json))
        return UpdateStatus.DONE
    }

    private suspend fun updateSharedPrefs(appContext: Context, tag: String, name: String) {
        update(appContext, dlpVersionKey, tag)
        update(appContext, dlpVersionNameKey, name)
    }

    @Throws(IOException::class)
    private suspend fun checkForUpdate(appContext: Context, youtubeDLChannel: UpdateChannel): JsonNode? =
        withContext(Dispatchers.IO) {
            val url = URL(youtubeDLChannel.apiUrl)
            val json = YoutubeDL.objectMapper.readTree(url)
            val newVersion = getTag(json)
            val oldVersion = SharedPrefsHelper[appContext, dlpVersionKey]
                return@withContext if (newVersion == oldVersion) null
                    else json
        }

    private fun getTag(json: JsonNode): String = json["tag_name"].asText()

    private fun getName(json: JsonNode): String = json["name"].asText()

    @Throws(YoutubeDLException::class)
    private suspend fun getDownloadUrl(json: JsonNode): String =
        withContext(Dispatchers.IO) {
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


    @Throws(IOException::class)
    private suspend fun download(appContext: Context, url: String): File =
        withContext(Dispatchers.IO) {
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

    fun version(appContext: Context?): String? {
        return SharedPrefsHelper[appContext!!, dlpVersionKey]
    }

    fun versionName(appContext: Context?): String? {
        return SharedPrefsHelper[appContext!!, dlpVersionNameKey]
    }
}