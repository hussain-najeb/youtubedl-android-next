package org.foss.youtube.next.example

import android.content.Context
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.workDataOf
import org.foss.youtube.next.YoutubeDL
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.UUID


// All metadata for the example video
data class DownMetadata(
    val title: String,
    val thumbnail: String?,
    val url: String
)

sealed class DownloadState {
    data object Idle : DownloadState()
    data object Loading : DownloadState()
    data class Downloading(val progress: Float, val metadata: DownMetadata?) : DownloadState()
    data class Finished(val metadata: DownMetadata) : DownloadState()
    data class Error(val error: String) : DownloadState()
}

enum class Video(val videoQuality: String) {
    HD1080("bv*[height<=1080]+ba/b[height<=1080]"),
    HD720("bv*[height<=720]+ba/b[height<=720]"),
    SD480("bv*[height<=480]+ba/b[height<=480]"),
    Q360("bv*[height<=360]+ba/b[height<=360]"),
    Q240("bv*[height<=240]+ba/b[height<=240]"),
    Q144("bv*[height<=144]+ba/b[height<=144]")
}

enum class Audio(val audioQuality: String) {
    BEST("0"),
    HIGH("2"),
    MEDIUM("5"),
    LOW("9")
}

const val VIDEO = "video"
const val AUDIO = "audio"
const val URL = "url"

class DownloadViewModel : ViewModel() {

    companion object {
        private const val WORK_ID = "active-download"
    }

    var state by mutableStateOf<DownloadState>(DownloadState.Idle)
    var downloadUrl by mutableStateOf("")
    var downloaderLogs by mutableStateOf("")
    private var activeProcess by mutableStateOf<UUID?>(null)
    private var job: Job? = null
    private var metadata: DownMetadata? = null


    fun Downloader(
        context: Context,
        audio: Audio? = null,
        video: Video? = null
    ) {

        if (activeProcess != null) return

        val request = OneTimeWorkRequestBuilder<DownWorker>()
            .setInputData(
                workDataOf(
                    URL to downloadUrl,
                    AUDIO to audio?.name,
                    VIDEO to video?.name
                )
            ).build()
        state = DownloadState.Loading
        metadata = null
        downloaderLogs = ""
        activeProcess = request.id

        job = viewModelScope.launch {
            try {
                val workManager = WorkManager.getInstance(context)
                workManager.enqueueUniqueWork(
                    WORK_ID,
                    ExistingWorkPolicy.KEEP,
                    request
                )

                val workInfos = workManager
                    .getWorkInfosForUniqueWorkFlow(WORK_ID)
                    .first { it.isNotEmpty() }
                val workingId = workInfos.firstOrNull { it.id == request.id }?.id
                    ?: workInfos.firstOrNull { !it.state.isFinished }?.id

                if (workingId == null) {
                    activeProcess = null
                    state = DownloadState.Error("Download work was not enqueued")
                    return@launch
                }
                activeProcess = workingId

                workManager.getWorkInfoByIdFlow(workingId).collect { workInfo ->
                    workInfo ?: return@collect
                    when (workInfo.state) {
                        WorkInfo.State.ENQUEUED, WorkInfo.State.BLOCKED -> {
                            state = DownloadState.Loading
                        }

                        WorkInfo.State.RUNNING -> {
                            val logs = workInfo.progress.getString("text")
                            if (!logs.isNullOrBlank()) {
                                downloaderLogs += logs
                            }

                            if (metadata == null) {
                                workInfo.progress.getString("metadata")?.let { json ->
                                    metadata = parser(json)
                                }
                            }

                            state = DownloadState.Downloading(
                                progress = workInfo.progress.getFloat("progress", 0f),
                                metadata = metadata
                            )
                        }

                        WorkInfo.State.SUCCEEDED -> {
                            val completedMetadata = metadata
                                ?: workInfo.outputData.getString("metadata")?.let(::parser)

                            state = DownloadState.Finished(
                                metadata = completedMetadata ?: DownMetadata(
                                    url = downloadUrl,
                                    title = "Download complete",
                                    thumbnail = null
                                )
                            )
                            activeProcess = null
                            downloaderLogs = ""
                        }

                        WorkInfo.State.FAILED -> {
                            val error = workInfo.outputData.getString("error")
                                ?: "Download failed without an error message"
                            state = DownloadState.Error(error)
                            activeProcess = null
                            metadata = null
                        }

                        WorkInfo.State.CANCELLED -> {
                            state = DownloadState.Idle
                            activeProcess = null
                            downloaderLogs = ""
                            metadata = null
                        }
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e("download viewmodel", "download viewmodel failed", e)
                activeProcess = null
                errorHandle(e)
            }
        }
    }

    fun cancel(context: Context) {
        activeProcess?.let { id ->
            YoutubeDL.destroyProcessById(id)
            WorkManager.getInstance(context).cancelWorkById(id)
        }
        job?.cancel()
        job = null
        state = DownloadState.Idle
        downloadUrl = ""
        downloaderLogs = ""
        activeProcess = null
        metadata = null
    }

        private fun errorHandle(e: Exception) {
            Log.e("error viewmodel", "Fetch failed: ${e.javaClass.simpleName}", e)
            val raw = when (e) {
                is TimeoutCancellationException -> "Timed out waiting for a response, check network connection"
                else -> e.message ?: e.toString()
            }
            state = DownloadState.Error(raw)
        }


    private fun parser(json: String): DownMetadata? {
        return try {
            val obj = JSONObject(json)
            fun optStringOrNull(key: String): String? {
                if (!obj.has(key) || obj.isNull(key)) return null
                return obj.optString(key).ifBlank { null }
            }

            val title = optStringOrNull("title") ?: "Unknown title"
            val thumbnail = optStringOrNull("thumbnail")
            val url = optStringOrNull("webpage_url")
            DownMetadata(
                url = url ?: return null,
                title = title,
                thumbnail = thumbnail,
            )

        } catch (e: Exception) {
            Log.e("downloader parsing", "JSON metadata parser failure", e)
            null
        }
    }
}
