package com.yausername.youtubedl_android_example

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.runBlocking

fun Download(
    url: String,
    id: String,
    callback: (Float ,String) -> Unit
) {
    val request = YoutubeDLRequest(url)
    YoutubeDL.getInstance().execute(request, id) { progress, _, string ->
        callback(progress ,string)
    }
}


class DownWorker(context: Context, param: WorkerParameters): CoroutineWorker(context, param) {
    override suspend fun doWork(): Result {

        val requestedUrl = inputData.getString("url")
        val Id = id.toString()
        val metadata: String? = null


        Download(
            url = requestedUrl,
            id = Id,
            callback = { progress, logs ->

                val currentProgress = progress.coerceIn(0f, 100f)

                runBlocking {
                    setProgress(
                        workDataOf(
                            "progress" to currentProgress,
                            "text" to logs,
                            "metadata" to metadata
                        )
                    )
                }
            }
        )
    }
}