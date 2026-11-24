package org.foss.youtube.common.prefs

import android.content.Context
import androidx.core.content.edit

object SharedPrefsHelper {
    private const val sharedPrefsName = "youtubedl-android"

    fun update(appContext: Context, key: String?, value: String?) {
        val pref = appContext.getSharedPreferences(sharedPrefsName, Context.MODE_PRIVATE)
        pref.edit {
            putString(key, value)
        }
    }

    operator fun get(appContext: Context, key: String?): String? {
        val pref = appContext.getSharedPreferences(sharedPrefsName, Context.MODE_PRIVATE)
        return pref.getString(key, null)
    }
}
