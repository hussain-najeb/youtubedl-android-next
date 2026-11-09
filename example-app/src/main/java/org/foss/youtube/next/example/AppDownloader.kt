package org.foss.youtube.next.example

import android.content.Context
import android.os.Environment
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import org.foss.youtube.next.YoutubeDL
import org.foss.youtube.next.YoutubeDLRequest
import kotlinx.coroutines.runBlocking
import java.io.File
import java.util.UUID

const val METADATA = "METADATA:"

suspend fun Download(
    context: Context,
    url: String,
    id: UUID,
    audio: Audio? = Audio.HIGH,
    video: Video? = Video.SD480,
    callback: (Float, String) -> Unit
) {
    val baseDir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: context.filesDir
    val downDir = File(baseDir, id.toString()).apply { mkdirs() }
    val finalDir = "${downDir.absolutePath}/%(title)s.%(ext)s"
    val request = YoutubeDLRequest(url)


    request.addOption("--no-simulate")
    request.addOption("--progress")
    request.addOption("--print", "info:$METADATA%(.{id,title,thumbnail,ext,webpage_url})j")

    audio?.let {
        request.addOption("-x")
        request.addOption("--audio-format", "opus") // change if having issues with opus for some reason
        request.addOption("--audio-quality", it.audioQuality)
    }

    video?.let { request.addOption("-f", it.videoQuality) }

    request.addOption("-v")
    request.addOption("-i")
    request.addOption("--embed-metadata")
    request.addOption("-o", finalDir)

    // Make "redirectErrorStream = true" false to have normal progress and thumbnail, only turn it to true for debugging.
    YoutubeDL.getInstance().execute(request, id, redirectErrorStream = true) { progress, _, log ->
        Log.d("YoutubeDL", log)
        callback(progress, log)
    }
}


class DownWorker(context: Context, param: WorkerParameters) : CoroutineWorker(context, param) {
    override suspend fun doWork(): Result {

        val requestedUrl = inputData.getString(URL)
        val audioInfo = inputData.getString(AUDIO)
        val videoInfo = inputData.getString(VIDEO)
        val audio = audioInfo?.let(Audio::valueOf)
        val video = videoInfo?.let(Video::valueOf)
        var metadata: String? = null
        val id = id

        return try {
            Download(
                context = applicationContext,
                url = requestedUrl ?: "",
                id = id,
                video = video,
                audio = audio,
                callback = { progress, logs ->
                    if (metadata == null) {
                        val index = logs.indexOf(METADATA)
                        if (index >= 0) {
                            metadata = logs.substring(index + METADATA.length).trim()
                        }
                    }
                    val measuredProgress = progress.coerceIn(0f,100f)

                    runBlocking {
                        setProgress(
                            workDataOf(
                                "progress" to measuredProgress,
                                "text" to logs,
                                "metadata" to metadata
                            )
                        )
                    }
                }
            )
            metadata?.let {
                Result.success(workDataOf("metadata" to it))
            } ?: Result.success()
        } catch (e: Exception) {
            val error = e.message
                ?.take(10_000)
                ?: "Download failed"
            Result.failure(workDataOf("error" to error))
        }
    }
}
