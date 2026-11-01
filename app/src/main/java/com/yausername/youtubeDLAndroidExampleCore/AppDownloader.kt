package com.yausername.youtubeDLAndroidExampleCore

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.runBlocking


const val METADATA = "METADATA:"


fun Download(
    url: String,
    id: String,
    audio: Audio? = Audio.HIGH,
    video: Video? = Video.SD480,
    callback: (Float, String) -> Unit
) {
    val request = YoutubeDLRequest(url)


    audio?.let {
        request.addOption("-x")
        request.addOption("--audio-format", "opus") // change if having issues with opus for some reason
        request.addOption("--audio-quality", it.audioQuality)
    }

    video?.let {
        request.addOption("-f", it.videoQuality)
    }


    YoutubeDL.getInstance().execute(request, id) { progress, _, string ->
        callback(progress, string)
    }
}


class DownWorker(context: Context, param: WorkerParameters) : CoroutineWorker(context, param) {
    override suspend fun doWork(): Result {


        val requestedUrl = inputData.getString(URL)
        val Id = id.toString()
        val audioInfo = inputData.getString(AUDIO)
        val videoInfo = inputData.getString(VIDEO)
        val audio = audioInfo?.let(Audio::valueOf)
        val video = videoInfo?.let(Video::valueOf)
        var metadata: String? = null

        return try {
            Download(
                url = requestedUrl ?: "",
                id = Id,
                video = video,
                audio = audio,
                callback = { progress, logs ->


                    if (metadata == null) {
                        val index = logs.indexOf(METADATA)
                        if (index != 1) {
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