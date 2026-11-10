package org.foss.youtube.next

import android.content.Context
import android.os.Process.sendSignal
import android.util.Log
import com.fasterxml.jackson.databind.ObjectMapper
import org.foss.youtube.next.mapper.VideoInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.apache.commons.io.FileUtils
import org.foss.youtube.common.prefs.SharedPrefsHelper
import org.foss.youtube.common.prefs.SharedPrefsHelper.update
import org.foss.youtube.common.prefs.Unpack.unzip
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.collections.set

object YoutubeDL {
    private var initialized = false
    private var pythonPath: File? = null
    private var ffmpegPath: File? = null
    private var aria2cPath: File? = null
    private var ytdlpPath: File? = null
    private var binDir: File? = null
    private var ENV_LD_LIBRARY_PATH: String? = null
    private var ENV_SSL_CERT_FILE: String? = null
    private var ENV_PYTHONHOME: String? = null
    private var ENV_ARIA2_OPENSSL_CONF: String? = null
    private var ENV_ARIA2_OPENSSL_MODULES: String? = null
    private var TMPDIR: String = ""
    private val updateMutex = Mutex()
    private val initMutex = Mutex()


    private class ProcessEntry(
        val process: Process,
        @Volatile var pid: Int? = null,
        @Volatile var cancelling: Boolean = false,
    )

    private val processes = ConcurrentHashMap<UUID, ProcessEntry>()

    /**
     * You must include this in you MainActivity with lifecycleScope
     * to initialize the library with all of its binaries.
     */
    suspend fun initializeLib(appContext: Context) = withContext(Dispatchers.IO) {
        initMutex.withLock {
            if (initialized) return@withLock
            val baseDir = File(appContext.noBackupFilesDir, baseName)
            if (!baseDir.exists()) baseDir.mkdir()
            val packagesDir = File(baseDir, packagesRoot)
            binDir = File(appContext.applicationInfo.nativeLibraryDir)
            pythonPath = File(binDir, pythonBinName)
            ffmpegPath = File(binDir, ffmpegBinName)
            val pythonDir = File(packagesDir, pythonDirName)
            val ffmpegDir = File(packagesDir, ffmpegDirName)
            val aria2cDir = File(packagesDir, aria2cDirName)
            val ytdlpDir = File(baseDir, ytdlpDirName)
            ytdlpPath = File(ytdlpDir, ytdlpBin)
            ENV_LD_LIBRARY_PATH = pythonDir.absolutePath + "/usr/lib" + ":" +
                 ffmpegDir.absolutePath + "/usr/lib" + ":" +
                 aria2cDir.absolutePath + "/usr/lib" + ":" +
                 binDir!!.absolutePath
            ENV_SSL_CERT_FILE = pythonDir.absolutePath + "/usr/lib/python3.14/site-packages/certifi/cacert.pem"
            ENV_PYTHONHOME = pythonDir.absolutePath + "/usr"
            ENV_ARIA2_OPENSSL_CONF = File(aria2cDir, "usr/etc/tls/openssl.cnf").absolutePath
            ENV_ARIA2_OPENSSL_MODULES = File(aria2cDir, "usr/lib/ossl-modules").absolutePath
            TMPDIR = appContext.cacheDir.absolutePath
            initFFmpeg(appContext, ffmpegDir)
            initPython(appContext, pythonDir)
            initAria2Next(appContext, aria2cDir)
            initYtdlp(appContext, ytdlpDir)
            initialized = true
        }
    }

    private fun initFFmpeg(appContext: Context, ffmpegDir: File) {
        val ffmpegLib = File(binDir, ffmpegLibName)
        val ffmpegSize = ffmpegLib.length().toString()

        if (!ffmpegDir.exists() || shouldUpdateFFmpeg(appContext, ffmpegSize)) {
            FileUtils.deleteQuietly(ffmpegDir)
            ffmpegDir.mkdirs()

            try {
                unzip(ffmpegLib, ffmpegDir)
            } catch (e: Exception) {
                FileUtils.deleteQuietly(ffmpegDir)
                throw YoutubeDLException("failed to initialize FFmpeg", e)
            }
            updateFFmpeg(appContext, ffmpegSize)
        }
    }

    private fun shouldUpdateFFmpeg(appContext: Context, version: String): Boolean {
        return version != SharedPrefsHelper[appContext, ffmpegLibVersion]
    }

    private fun updateFFmpeg(appContext: Context, version: String) {
        update(appContext, ffmpegLibVersion, version)
    }

    fun initYtdlp(appContext: Context, ytdlpDir: File) {
        if (!ytdlpDir.exists()) ytdlpDir.mkdirs()
        val ytdlpBinary = File(ytdlpDir, ytdlpBin)
        if (!ytdlpBinary.exists()) {
            try {
                val inputStream =
                    appContext.resources.openRawResource(R.raw.ytdlp) /* will be renamed to yt-dlp */
                FileUtils.copyInputStreamToFile(inputStream, ytdlpBinary)
            } catch (e: Exception) {
                FileUtils.deleteQuietly(ytdlpDir)
                throw YoutubeDLException("failed to initialize", e)
            }
        }
    }

    fun initPython(appContext: Context, pythonDir: File) {
        val pythonLib = File(binDir, pythonLibName)
        // using size of lib as version
        val pythonSize = pythonLib.length().toString()

        if (!pythonDir.exists() || shouldUpdatePython(appContext, pythonSize)) {
            FileUtils.deleteQuietly(pythonDir)
            pythonDir.mkdirs()

            try {
                unzip(pythonLib, pythonDir)
            } catch (e: Exception) {
                FileUtils.deleteQuietly(pythonDir)
                throw YoutubeDLException("failed to initialize", e)
            }

            updatePython(appContext, pythonSize)
        }

        FileUtils.deleteQuietly(
            File(pythonDir, "usr/lib/liblzma.so")
        )
    }

    private fun shouldUpdatePython(appContext: Context, version: String): Boolean {
        return version != SharedPrefsHelper[appContext, pythonLibVersion]
    }

    private fun updatePython(appContext: Context, version: String) {
        update(appContext, pythonLibVersion, version)
    }

    fun initAria2Next(appContext: Context, aria2cDir: File) {
        val aria2cLib = File(binDir, aria2cLibName)
        val aria2cSize = aria2cLib.length().toString()

        if (!aria2cDir.exists() || shouldUpdateAria2c(appContext, aria2cSize)) {
            FileUtils.deleteQuietly(aria2cDir)
            aria2cDir.mkdirs()
            try {
                unzip(aria2cLib, aria2cDir)
            } catch (e: Exception) {
                FileUtils.deleteQuietly(aria2cDir)
                throw YoutubeDLException("failed to initialize aria2c", e)
            }
            updateAria2c(appContext, aria2cSize)
        }

        aria2cPath = File(binDir, aria2cBinName)
        val aria2cBinary = aria2cPath!!

        if (!aria2cBinary.exists()) {
            throw YoutubeDLException(
                "aria2c native executable not found at ${aria2cBinary.absolutePath}"
            )
        }

        if (!aria2cBinary.canExecute()) {
            throw YoutubeDLException(
                "aria2c native executable is not executable at ${aria2cBinary.absolutePath}"
            )
        }
    }

    private fun shouldUpdateAria2c(appContext: Context, version: String): Boolean {
        return version != SharedPrefsHelper[appContext, aria2cLibVersion]
    }

    private fun updateAria2c(appContext: Context, version: String) {
        update(appContext, aria2cLibVersion, version)
    }

    private fun assertInit() {
        check(initialized) { "instance not initialized" }
    }

    private fun ignoreErrors(request: YoutubeDLRequest, out: String): Boolean {
        return request.hasOption("--dump-json") && out.isNotEmpty() && request.hasOption("--ignore-errors")
    }

    private fun waitForIdRelease(
        processId: UUID,
        timeout: Long = 2000L,
        confirmation: Long = 50L
    ): Boolean {
        val deadline = System.currentTimeMillis() + timeout
        while (System.currentTimeMillis() < deadline) {
            if (!processes.containsKey(processId)) return true
            Thread.sleep(confirmation)
        }
        return !processes.containsKey(processId)
    }

    private fun lingeringProcessTermination(entry: ProcessEntry) {
        val pid = entry.pid
        if (pid != null) {
            destroyChildProcesses(pid)
            sendSignal(pid, 9)
        } else {
            entry.process.destroy()
        }
    }

    private fun readPidFile(pidFile: File): Int? {
        repeat(50) {
            val pid = if (pidFile.exists()) pidFile.readText().trim().toIntOrNull() else null
            if (pid != null) return pid
            Thread.sleep(50)
        }
        return null
    }


    /**
    For apps that use this library, this function is to be called to cancel the process.
    Usually you would have an ID that reefers to the WorkManager ID that you would have.


    Check the example app code of the library for the optimal integration.
     */
    fun destroyProcessById(id: UUID): Boolean {
        val entry = processes[id] ?: return false
        Log.d("YoutubeDLRace", "cancel requested id=$id")

        entry.cancelling = true
        return try {
            lingeringProcessTermination(entry)
            true
        } catch (e: Exception) {
            Log.e("YoutubeDLRace", "Failed to terminate process id=$id", e)
            false
        }
    }

    /**
    Shell command function with the only purpose of finding and terminating
    A yt-dlp process
     */
    private fun destroyChildProcesses(pid: Int): Boolean {
        return try {
            val executionCommand = """
            kill_descendants() {
                for child in ${'$'}(cat "/proc/${'$'}1/task/${'$'}1/children" 2>/dev/null); do
                    kill_descendants "${'$'}child"
                    kill -KILL "${'$'}child" 2>/dev/null
                done
            }
            kill_descendants $pid
        """.trimIndent()
            val terminator = ProcessBuilder(
                "/system/bin/sh",
                "-c",
                executionCommand
            ).start()
            terminator.waitFor() == 0
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            Log.e("YoutubeDL", "Child termination interrupted", e)
            false
        } catch (e: Exception) {
            Log.e("YoutubeDL", "Failed to terminate descendants of $pid", e)
            false
        }
    }


    /** This function is a convenience function around getInfo(request: YoutubeDLRequest): VideoInfo
    Use this function for the default yt-dlp request
     */
    suspend fun getInfo(url: String): VideoInfo = getCustomInfo(YoutubeDLRequest(url))

    /**
    Use this function directly if you have a custom request.
     */
    suspend fun getCustomInfo(request: YoutubeDLRequest): VideoInfo {
        request.addOption("--dump-json")
        val response = execute(request)
        return try {
            objectMapper.readValue(response.out, VideoInfo::class.java)
        } catch (e: IOException) {
            throw YoutubeDLException("Unable to parse video information: ${response.err}", e)
        } ?: throw YoutubeDLException("Failed to fetch video information")
    }


    class CanceledException : Exception()

    suspend fun execute(
        request: YoutubeDLRequest,
        processId: UUID? = null,
        redirectErrorStream: Boolean = false,
        callback: ((Float, Long, String) -> Unit)? = null
    ): YoutubeDLResponse = runInterruptible(Dispatchers.IO) { executeImplementation(request, processId, redirectErrorStream, callback) }


    private fun executeImplementation(
        request: YoutubeDLRequest,
        processId: UUID? = null,
        redirectErrorStream: Boolean = false,
        callback: ((Float, Long, String) -> Unit)? = null
    ): YoutubeDLResponse {
        assertInit()
        var entry: ProcessEntry? = null

        if (processId != null && !waitForIdRelease(processId)) {
            throw YoutubeDLException("Process ID already exists")
        }
        // disable caching unless explicitly requested
        if (!request.hasOption("--cache-dir") || request.getOption("--cache-dir") == null) {
            request.addOption("--no-cache-dir")
        }
        // To use curl_cffi and curl_impersonate!
        request.addOption("--impersonate","chrome")
        // To use QuickJS-NG as the JS solver
        val quickJsCli = File(requireNotNull(binDir), "libqjs-cli.so")
        if (quickJsCli.exists()) request.addOption("--js-runtimes", "quickjs:${quickJsCli.absolutePath}")

        // this sets aria2 Next as on by default
        if (request.buildCommand().contains("libaria2c.so")) {
            request
                .addOption("--external-downloader-args", "aria2c:--summary-interval=1")
                .addOption(
                    "--external-downloader-args",
                    "aria2c:--ca-certificate=$ENV_SSL_CERT_FILE"
                )
        }
        request.addOption("--ffmpeg-location", ffmpegPath!!.absolutePath)
        val process: Process
        val exitCode: Int
        val stdout = StringBuffer()
        val stderr = StringBuffer()
        val startTime = System.currentTimeMillis()

        val arguments = request.buildCommand().map { arg ->
            if (arg == "libaria2c.so") {
                aria2cPath!!.absolutePath
            } else {
                arg
            }
        }
        val pidFile = processId?.let {
            File(TMPDIR, "ytdlp-$it.pid").apply {
                FileUtils.deleteQuietly(this)
            }
        }
        val command: MutableList<String?> = ArrayList()

        if (pidFile != null) {
            val shellCommand = """
        echo ${'$'}${'$'} > "${pidFile.absolutePath}"
        exec "${'$'}@"
    """.trimIndent()
            command.addAll(
                listOf(
                    "/system/bin/sh",
                    "-c",
                    shellCommand,
                    "sh",
                    pythonPath!!.absolutePath,
                    ytdlpPath!!.absolutePath
                )
            )
        } else {
            command.addAll(
                listOf(
                    pythonPath!!.absolutePath,
                    ytdlpPath!!.absolutePath
                )
            )
        }

        command.addAll(arguments)
        val processBuilder = ProcessBuilder(command)
            .redirectErrorStream(redirectErrorStream)

        processBuilder.environment().apply {
            this["LD_LIBRARY_PATH"] = ENV_LD_LIBRARY_PATH
            this["SSL_CERT_FILE"] = ENV_SSL_CERT_FILE
            this["PATH"] = System.getenv("PATH").orEmpty() + ":" + binDir!!.absolutePath + ":" + aria2cPath!!.parentFile!!.absolutePath
            this["PYTHONHOME"] = ENV_PYTHONHOME
            this["OPENSSL_CONF"] = ENV_ARIA2_OPENSSL_CONF
            this["OPENSSL_MODULES"] = ENV_ARIA2_OPENSSL_MODULES
            this["HOME"] = ENV_PYTHONHOME
            this["TMPDIR"] = TMPDIR
        }

        process = try {
            processBuilder.start()
        } catch (e: IOException) {
            throw YoutubeDLException(e)
        }

        if (processId != null) {
            val newEntry = ProcessEntry(process)
            if (processes.putIfAbsent(processId, newEntry) != null) {
                process.destroy()
                pidFile?.let { FileUtils.deleteQuietly(it) }
                throw YoutubeDLException("Process ID already exists")
            }
            entry = newEntry
            Log.d("YoutubeDLRace", "registered id=$processId")
            pidFile?.let { readPidFile(it)?.let { pid -> newEntry.pid = pid }
                FileUtils.deleteQuietly(it)
            }
        }

        try {
            val outStream = process.inputStream
            val errStream = process.errorStream
            val stdOutProcessor = StreamProcessExtractor(stdout, outStream, callback)
            val stdErrProcessor = StreamGobbler(stderr, errStream)

            exitCode = try {
                stdOutProcessor.join()
                stdErrProcessor.join()
                process.waitFor()
            } catch (e: InterruptedException) {
                entry?.let { lingeringProcessTermination(it) } ?: process.destroy()
                throw e
            }

            val out = stdout.toString()
            val err = stderr.toString()

            if (exitCode > 0) {
                if (entry != null && entry.cancelling) throw CanceledException()
                if (!ignoreErrors(request, out)) throw YoutubeDLException(err)
            }
            val elapsedTime = System.currentTimeMillis() - startTime

            val youtubeDLResponse = YoutubeDLResponse(command, exitCode, elapsedTime, out, err)
            return youtubeDLResponse
        } finally {
            if (processId != null && entry != null) processes.remove(processId, entry)
        }
    }

    /**
     * This is a suspend function with a mutex, it fetches new versions of **yt-dlp**
     * then compares them to the exiting version, if there was
     * a diversion, the function will replace the exiting version
     * with the new **yt-dlp** version
     */
    suspend fun updateYoutubeDL(
        appContext: Context,
        updateChannel: UpdateChannel = UpdateChannel.Nightly
    ): UpdateStatus? {
        assertInit()
        return try {
            updateMutex.withLock {
                YoutubeDLUpdater.update(appContext, updateChannel)
            }
        } catch (e: IOException) {
            throw YoutubeDLException("failed to update youtube-dl", e)
        }
    }

    /**
     * This returns something like "2026.08.30.232658", just the version number of **yt-dlp**.
     * For the stable version of **yt-dlp**, it’s a plain date like 2026.08.30.
     */
    fun versionNumber(appContext: Context?): String? {
        return YoutubeDLUpdater.version(appContext)
    }

    /**
     * This one returns the release title shown on GitHub. For **yt-dlp** that is usually the tag with a prefix,
     * e.g. yt-dlp 2026.08.30, and for nightlies something like **yt-dlp** nightly 2026.08.30.232658
     */
    fun versionName(appContext: Context?): String? {
        return YoutubeDLUpdater.versionName(appContext)
    }


    /**
     * Pick **"Done"** when updating has finished,
     * **"AlreadyUpToDate"** when the update function doesn't find a new version
     */
    enum class UpdateStatus {
        Done, AlreadyUpToDate
    }

    private const val GITHUB = "https://api.github.com/repos"
    enum class UpdateChannel(val apiUrl: String) {
        Stable("$GITHUB/yt-dlp/yt-dlp/releases/latest"),
        Nightly("$GITHUB/yt-dlp/yt-dlp-nightly-builds/releases/latest"),
        Master("$GITHUB/yt-dlp/yt-dlp-master-builds/releases/latest")
    }


    const val baseName = "youtubedl-android"
    private const val packagesRoot = "packages"
    private const val pythonBinName = "libpython.so"
    private const val pythonLibName = "libpython.zip.so"
    private const val pythonDirName = "python"
    private const val ffmpegDirName = "ffmpeg"
    private const val ffmpegBinName = "libffmpeg.so"
    private const val ffmpegLibName = "libffmpeg.zip.so"
    private const val ffmpegLibVersion = "ffmpegLibVersion"
    private const val aria2cDirName = "aria2c"
    private const val aria2cBinName = "libaria2c.so"
    private const val aria2cLibName = "libaria2.zip.so"
    private const val aria2cLibVersion = "aria2cLibVersion"
    const val ytdlpDirName = "yt-dlp"
    const val ytdlpBin = "yt-dlp"
    private const val pythonLibVersion = "pythonLibVersion"
    val objectMapper = ObjectMapper()

    fun getInstance() = this
}
