package org.foss.youtube.next.example

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldColors
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.foss.youtube.next.example.ui.button.ButtonExample
import org.foss.youtube.next.example.ui.cards.Downloading
import org.foss.youtube.next.example.ui.cards.Error
import org.foss.youtube.next.example.ui.cards.Finished
import org.foss.youtube.next.example.ui.cards.Loading
import java.time.format.TextStyle

@Composable
fun MainApp(
    state: DownloadState,
    viewModel: DownloadViewModel
) {

    val context = LocalContext.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(color = Color(0xFF293141))
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(10.dp)
        ) {
            StateSwitch(
                state = state,
                viewModel = viewModel
            )
        }

        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            Column {
                Box(
                    modifier = Modifier
                        .padding(10.dp)
                ) {
                    OutlinedTextField(
                        value = viewModel.downloadUrl,
                        onValueChange = { text ->
                            viewModel.downloadUrl = text
                        },
                        textStyle = androidx.compose.ui.text.TextStyle(color = Color(0xFFfdfefe)),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(10.dp),
                        placeholder = {
                            Text(
                                text = "Enter Url",
                                color = Color(0xFF2b313c),
                                fontSize = 15.sp
                            )
                        },
                    )
                }
                Box(
                    modifier = Modifier
                        .padding(10.dp)
                        .fillMaxWidth()
                ) {
                    ButtonExample(
                        modifier = Modifier.fillMaxWidth(),
                        onClick = {
                            viewModel.Downloader(context)
                        },
                        text = "Download"
                    )
                }
            }
        }
    }
}


@Composable
fun StateSwitch(
    state: DownloadState,
    viewModel: DownloadViewModel,
) {

    val context = LocalContext.current

    AnimatedContent(
        targetState = state,
        transitionSpec = {
            (slideInVertically(
                animationSpec = tween(),
                initialOffsetY = { -it }
            ) + fadeIn(initialAlpha = 0.1f))
                .togetherWith(
                    exit = slideOutVertically(
                        animationSpec = tween(),
                        targetOffsetY = { -it }
                    ) + fadeOut(targetAlpha = 0.1f)
                )
        },
        label = "DownloaderCardTransition",
        contentKey = { it::class }
    ) { targetState ->
        when (targetState) {
            is DownloadState.Idle -> Unit

            is DownloadState.Loading -> {
                Loading(
                    onCancel = { viewModel.cancel(context) }
                )
            }

            is DownloadState.Downloading -> {
                targetState.metadata?.let { metadata ->
                    Downloading(
                        metadata = metadata,
                        progress = targetState.progress,
                        onCancel = { viewModel.cancel(context) },
                    )
                } ?: Loading(
                        onCancel = { viewModel.cancel(context) }
                )
            }

            is DownloadState.Finished -> {
                Finished(
                    targetState.metadata,
                    onCancel = { viewModel.cancel(context) },
                )
            }

            is DownloadState.Error -> {
                Error(
                    error = targetState.error,
                    onCancel = { viewModel.cancel(context) }
                )
            }
        }
    }
}