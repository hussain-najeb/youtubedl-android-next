package org.foss.youtube.next.example

import android.os.Bundle
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
            YoutubeDL.init(applicationContext)
        }

        setContent {
            MaterialTheme {
                MainApp(state = viewModel.state, viewModel = viewModel)
            }
        }
    }
}
