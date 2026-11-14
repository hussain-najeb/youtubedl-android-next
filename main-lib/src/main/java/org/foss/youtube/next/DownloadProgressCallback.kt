package org.foss.youtube.next

interface DownloadProgressCallback {
    fun onProgressUpdate(progress: Float, etaInSeconds: Long, line: String?)
}
