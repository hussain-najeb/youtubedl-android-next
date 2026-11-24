package org.foss.youtube.next.example

import android.content.ContentValues.TAG
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.lifecycle.lifecycleScope
import org.foss.youtube.next.YoutubeDL
import kotlinx.coroutines.launch

class MainActivity: ComponentActivity() {

    private val viewModel: DownloadViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        enableEdgeToEdge()
        lifecycleScope.launch {
            try {
                YoutubeDL.initializeLib(applicationContext)
            } catch (e: Exception) {
                Log.e(TAG, "failed to initialize youtubedl-android-next", e)
            }
        }

        setContent {
            MaterialTheme {
                MainApp(state = viewModel.state, viewModel = viewModel)
            }
        }
    }
}
