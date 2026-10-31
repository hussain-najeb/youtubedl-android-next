package com.yausername.youtubedl_android_example

import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest

fun Download(
    url: String
) {
    val request = YoutubeDLRequest(url)
    YoutubeDL.getInstance().execute(request )


}