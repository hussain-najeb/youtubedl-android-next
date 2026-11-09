## YoutubeDL-Android Next
---
> [!NOTE]
> This is an active fork of the library [**youtubedl-android**](https://github.com/yausername/youtubedl-android), with the following enhancements:
> 1. Updated every project dependency and build tooling used with its updated counterpart, like a newer version of **Kotlin**, **jackson**, and **gradle**.
> 2. **Updated** the library to have the UI Framework **Compose**, while removing the old xml/views system for the example app; this only affects the example app.
> 3. Modernizing the library to use modern **Kotlin** features, like coroutines and mutexes, while generally making the codebase more **Kotlin**-idiomatic, and making the codebase leaner.
> 4. Updated library **ffmpeg** from **7.0.2** to **9.0.2** and included a much wider support for audio and video encoding/decoding and the enablement of the hardware acceleration option by default.
> 5. Migrated the old library [**QuickJs**](https://bellard.org/quickjs/) to the new project [**QuickJS-NG**](https://github.com/quickjs-ng/quickjs) which is a maintained fork of the original with many enhancements.
> 6. Migrated the old library [**Aria2c**](https://github.com/aria2/aria2) to its actively maintained, modern reimplementation, [**Aria2-Next**](https://github.com/AnInsomniacy/aria2-next)!
> 7. Added library [**Curl-Cffi**](https://github.com/lexiforest/curl_cffi), which is a Python binding for Curl-Impersonate that enables Python applications to perform HTTP requests; basically, a convenient **interface** for Curl-Impersonate.
> 8. Added [**Curl-Impersonate**](https://github.com/hussain-najeb/curl-impersonate), a modified build of curl that can mimic the TLS and HTTP fingerprints of major browsers, like Chrome, allowing automated HTTP requests to closely resemble browser traffic.
> 9. Much more on the way!

> [!IMPORTANT]
> An elaboration on the first 3 points.
>
> In the process of modernizing the original library, a lot of code from the original codebase that had to do with **Java** was removed, in favor of **Kotlin**!
>
> *While that would make **Java**-based apps that use the old library have a much harder time using this project, it would be a much simpler task in terms of maintenance to have unification in the codebase, in a language that I personally have a much easier time writing with.*

# What is YoutubeDL?
---

**YoutubeDL** is a library that brings [**yt-dlp**](https://github.com/yt-dlp/yt-dlp) to **Android**. Usually, using the bare library on **Android** involved using a **[Termux](https://termux.dev/en/)** setup and doing a very finicky **Curl-Impersonate** setup that works without major work. With **YoutubeDL-Android Next**, this work has already been done to ensure the easiest way to use [**yt-dlp**](https://github.com/yt-dlp/yt-dlp) on **Android**, using an **updated stack**. The whole stack consists of:

| Library           |             Version |
| ----------------- | ------------------: |
| yt-dlp            |          2026.10.26 |
| QuickJS-NG        |             v0.18.0 |
| Aria2-Next        |             v3.0.10 |
| FFmpeg            |              v9.0.2 |
| Python            |            v3.14.10 |
| libffi            |              v3.8.0 |
| Android API Level |                  24 |
| Android NDK       | r30 (30.0.16248370) |
| CFFI              |               2.1.1 |
| Curl-CFFI         |            0.17.0b2 |
| Mutagen           |              1.48.1 |
| Certifi           |          2026.10.23 |
| cibuildwheel      |               4.3.5 |
| Termux Host LLVM  |                  21 |

> [!NOTE]
> All of these versions will probably be changed as part of a monthly update cycle.

# How To Use:
- - -
Generally, using this library shouldn't be difficult; you should do something like this:

### **Gradle**:

Open your `gradle/libs.versions.toml`, then add these:

- Add this to your `[versions]` block:
  ```TOML
  [versions]
  youtubedlNext = "0.1.0"
  ```

- Then, in your `[libraries]`, add:
  ```TOML
  youtubedl-android-next = { group = "io.github.hussain-najeb", name = "youtubedl-android-next", version.ref = "youtubedlNext" }
  ```

- Then in your app's `app/build.gradle.kts`:
  ```Kotlin
  dependencies {
      implementation(libs.youtubedl.android.next)
  }
  ```

- And **finally**, in the same file, add:
  ```Kotlin
  packaging {
      jniLibs {
          useLegacyPackaging = true
      }
  }
  ```

- Set `android:extractNativeLibs="true"` in your app's manifest.
- On Android 10 (API 29), set `android:requestLegacyExternalStorage="true"`.

>[!NOTE]
>This library isn’t published on JitPack. It is distributed through GitHub Packages (Maven).

### In your app code:

- You must first include it in your `MainActivity` with a `lifecycleScope`:
```kotlin
lifecycleScope.launch {
    try {
        YoutubeDL.initializeLib(applicationContext)
    } catch (e: Exception) {
        Log.e(TAG, "failed to initialize youtubedl-android-next", e)
    }
}
```

*This is here to initialize the library itself, with a `lifecycleScope` because `initializeLib` is a suspend function. Due to the nature of this fork, you don't need to call **ffmpeg** and **Aria2-Next** here; they are called by default.*


- This is how you get your request, i.e., the video URL:
```kotlin
val baseDir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: context.filesDir
val downDir = File(baseDir, id).apply { mkdirs() }
val finalDir = "${downDir.absolutePath}/%(title)s.%(ext)s"
val request = YoutubeDLRequest(url)
```

*The parameter "url" comes from the consumers of this library, check the example app for a better idea.*

> [!NOTE]
> The reason why this code uses `Environment.DIRECTORY_DOWNLOADS` is that on Android 10+ (API 29 or higher), due to Android's Scoped Storage changes, apps only have direct access to `Download/` and `Documents/`. This library uses the **Private Downloads** folder of the example app, but you can use the **MediaStore.Downloads** collection to manage downloads in the public downloads folder.


- You can add as many **yt-dlp** options as you want, by simply using the `addOption` function:
```kotlin
request.addOption("-v") // for verbose output
request.addOption("-o", finalDir) // for the output to end up in the app's private downloads directory
request.addOption("-i") // to ignore errors when they happen
```


- Then you get to use the **YoutubeDL** object:
```kotlin
YoutubeDL.getInstance().execute(request, id, redirectErrorStream = false) { progress, _, string ->
    callback(progress, string)
}
```

This snippet means that you call the object, get an instance, then call the execution function `execute`. You add in your `request` as we established, then your own `id` for the video, usually provided from `WorkManager`, then turn off `redirectErrorStream` (this param is for testing, so always turn it off), then use the `callback` param to supply your **download progress** and **logs**.

- To reliably get **progress**, use something like this:
```kotlin
request.addOption("--progress")
```

- The process of updating **yt-dlp** should be simple, you should use `updateYoutubeDL`:
```kotlin
val updateChannel = when (channel) {
    YtdlpChannel.Stable -> YoutubeDL.UpdateChannel.STABLE
    YtdlpChannel.Nightly -> YoutubeDL.UpdateChannel.NIGHTLY
    YtdlpChannel.Master -> YoutubeDL.UpdateChannel.MASTER
}
```

The `channel` is just the enum `YtdlpChannel`, which has the 3 values that were declared to match each `YoutubeDL` channel.

Then use what goes out by using the `updateYoutubeDL` function now:
```kotlin
val result = YoutubeDL.getInstance().updateYoutubeDL(
    appContext = getApplication(),
    updateChannel = updateChannel
)
```

Then this `result` can be used in any way you want, whether it's a `viewModel` or anything else.

- If you wish to cancel a request, you can use `destroyProcessById`:
```kotlin
YoutubeDL.destroyProcessById(id)
```

This "id" param comes from the `WorkManager` UUID; it is highly advised to inspect the [example app's](https://github.com/hussain-najeb/youtubedl-android-next/blob/master/example-app/src/main/java/org/foss/youtube/next/example/DownloadViewModel.kt) code for a better picture.

> [!NOTE]
> You dont need `getInstance()` to cancel requests.


## FFmpeg
- - -
**ffmpeg** in this project has all external libraries enabled using [ffmpeg-android-maker](https://github.com/Javernaut/ffmpeg-android-maker). The compilation process includes `-enable-all-free`, which means adding all these libraries to ffmpeg:

| Library     | flag                   | alias               |
| :---------- | ---------------------- | ------------------- |
| libaom      | `--enable-libaom`      | `-aom`              |
| libbluray   | `--enable-libbluray`   | `-bluray`           |
| libdav1d    | `--enable-libdav1d`    | `-dav1d`            |
| libfreetype | `--enable-libfreetype` | `-freetype`         |
| libfribidi  | `--enable-libfribidi`  | `-fribidi`          |
| libmp3lame  | `--enable-libmp3lame`  | `-mp3lame`, `-lame` |
| libopus     | `--enable-libopus`     | `-opus`             |
| libspeex    | `--enable-libspeex`    | `-speex`            |
| libtwolame  | `--enable-libtwolame`  | `-twolame`          |
| libvpx      | `--enable-libvpx`      | `-vpx`              |
| libwavpack  | `--enable-libwavpack`  | `-wavpack`          |
| libwebp     | `--enable-libwebp`     | `-webp`             |
| libx264     | `--enable-libx264`     | `-x264`             |

All these libraries are included with the shipped **ffmpeg** and **ffprobe**, which can be used by **yt-dlp** for more options, such as switching to other audio formats like `opus` or `mp3` and other video containers like `WebM` or `MKV`. It allows you to embed thumbnails, subtitles, and detailed metadata directly into the final file.

Also, you can easily swap containers (e.g., moving video into a `WebM` or `Ogg` container) without re-encoding, preserving the original quality while changing the file extension.


## Aria2-Next
- - -
- You can use Aria2 Next as a different option from the default downloader with:
```kotlin
val aria2Argument = "aria2c:--summary-interval=1 -x 12 -s 12 -k 1M"
request.addOption("--downloader", "libaria2c.so")
request.addOption("--external-downloader-args", aria2Argument)
```

This makes **Aria2-Next** usage possible; you can use all the **Aria2c** commands as **Aria2-Next** uses the same commands!


#### What is Aria2 Next?

**Aria2-Next** is a fork of the original **aria2c** library, which brings many bug fixes and modernizes many sides of the original project with a different new engine. The library still keeps what users and frontends rely on: the `aria2` command line, configuration files, session files, etc., with a new engine behind them.

This library doesn't currently exist in the **Termux-packages**, for now at least, but it was tested on all Android APIs and built using cross-compilation to support Android architectures other than the ones that the library comes with, which was only arm64.

To get more details on the project, [visit this page](https://github.com/AnInsomniacy/aria2-next/blob/main/README.md).


## QuickJS-NG
- - -
In **youtubedl-android Next**, you don't have to use anything for **QuickJS-NG** to work, it works out-of-the-box.

**QuickJS-NG** is an actively maintained fork of the [original QuickJS project](https://bellard.org/quickjs) by Fabrice Bellard and Charlie Gordon, it is a lightweight embeddable JavaScript engine. It aims to support the latest [ECMAScript](https://tc39.es/ecma262/) specification.

**yt-dlp** uses **QuickJS** this way: yt-dlp needs a JavaScript runtime to execute the player code YouTube serves (for example, to solve the signature and “n” parameter challenges that gate video URLs). Historically it used its own built-in interpreter (JSInterpreter), which was limited and slow. Newer versions can instead use an external JS runtime such as Node, Bun, or QuickJS, which is more robust as YouTube’s player code gets more complex.


## Curl-Impersonate
- - -
In **youtubedl-android Next**, you also don't have to do anything for TLS and impersonation to work, it works out-of-the-box with [**Curl-Impersonate**](https://github.com/hussain-najeb/curl-impersonate), an active fork that works with [**Curl-Cffi**](https://github.com/lexiforest/curl_cffi), all **cross-compiled** for every **Android ABI**, which makes it much easier to download videos from YouTube, TikTok, Instagram, and many, many more websites that weren't possible to download without major errors. This, inadvertently, makes **yt-dlp** much more reliable when making requests!

And unlike other projects, **both libraries** that were added (Curl-Cffi, Curl-Impersonate) were **cross-compiled** to work on **all Android architectures**! `arm64-v8a`, `armeabi-v7a`, `x86`, and `x86_64`.


> [!NOTE]
> All of this can be inspected in the [build-scripts]("add Url here") with **Curl-Cffi** as well.


## Documentation and Build Scripts
- - -
This library has three modules, two of which are linked: `natives` and `main-lib`. The third is `example-app` (the demo app, which isn't released). That doesn't change the fact that you only need one line to implement this library: Gradle will use `natives`, as it contains all the `.so` files that `main-lib` uses. The split only exists to make the library's update cycle easier.

You do not need to inspect the build scripts to use the project. However, if you are interested in how the native components are built for the supported Android ABIs, refer to [Build Documentation](BUILD-ALL.md).

If you encounter an issue with any of the build scripts, please report it so that it can be investigated and corrected.
