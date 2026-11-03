package org.foss.youtube.next.example.ui.cards

import android.content.ClipData
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontWeight.Companion.W500
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import org.foss.youtube.next.example.DownMetadata
import org.foss.youtube.next.example.DownloadState
import org.foss.youtube.next.example.ui.button.ButtonExample

@Composable
fun Loading(
    onCancel: () -> Unit
) {

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(10.dp)
    ) {
        Surface(
            modifier = Modifier
                .aspectRatio(16f / 9f),
            shape = RoundedCornerShape(8.dp),
            shadowElevation = 5.dp,
            color = Color(0xFF434c5e)
        ) {
            Box(
                modifier = Modifier.fillMaxWidth().padding(24.dp),
                contentAlignment = Alignment.Center
            ) {
                LoadingIndicator(
                    modifier = Modifier.size(60.dp),
                    color = Color(0xFF719395)
                )
            }
        }

        Box(modifier = Modifier.fillMaxWidth()) {
            ButtonExample(
                modifier = Modifier.fillMaxWidth(),
                onClick = onCancel,
                text = "Cancel"
            )
        }
    }
}

@Composable
fun Downloading(
    metadata: DownMetadata?,
    progress: Float,
    onCancel: () -> Unit
) {

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(10.dp)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 9f)
                .background(Color(0xFF434c5e)),
            shape = RoundedCornerShape(8.dp),
            shadowElevation = 5.dp
        ) {
            AsyncImage(
                model = metadata?.thumbnail,
                contentDescription = null,
                contentScale = ContentScale.Crop
            )
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 10.dp)
        ) {
            Surface(
                modifier = Modifier
                    .height(60.dp)
                    .padding(bottom = 5.dp)
                    .fillMaxWidth(),
                shape = RoundedCornerShape(8.dp),
                color = Color(0xFF434c5e),
                shadowElevation = 5.dp
            ) {
                Box(
                    modifier = Modifier
                        .padding(10.dp)
                        .fillMaxHeight(),
                    contentAlignment = Alignment.CenterStart
                ) {
                    Text(
                        text = "Downloading: %$progress",
                        color = Color.White,
                        fontSize = 18.sp,
                        fontWeight = W500
                    )
                }
            }
            ButtonExample(
                modifier = Modifier.fillMaxWidth(),
                onClick = onCancel,
                text = "Cancel"
            )
        }
    }
}

@Composable
fun Error(
     error: String,
     onCancel: () -> Unit
) {

    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    val scrollState = rememberScrollState()

    Column(
        modifier = Modifier
            .padding(10.dp)
            .fillMaxSize()
    ) {
        Surface(
            modifier = Modifier
                .aspectRatio(16f / 9f),
            shape = RoundedCornerShape(8.dp),
            color = Color(0xFF434c5e),
            shadowElevation = 5.dp
        ) {
            Column(
                modifier = Modifier
                    .verticalScroll(scrollState)
            ) {
                Text(
                    text = error,
                    color = Color(0xFFdb877f),
                    fontSize = 16.sp,
                    fontWeight = W500,
                    modifier = Modifier
                        .padding(15.dp)
                )
            }
        }
        Column {
            ButtonExample(
                modifier = Modifier.fillMaxWidth(),
                onClick = onCancel,
                text = "Retry"
            )
            ButtonExample(
                modifier = Modifier.fillMaxWidth(),
                onClick = {
                    scope.launch {
                        val clipData = ClipData.newPlainText("youtube error", error)
                        clipboard.setClipEntry(ClipEntry(clipData))
                    }
                },
                text = "Copy Error"
            )
        }
    }
}


@Composable
fun Finished(
    metadata: DownMetadata?,
    onCancel: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(10.dp)
    ) {
        Surface(
            modifier = Modifier
                .aspectRatio(16f / 9f),
            shape = RoundedCornerShape(8.dp),
            color = Color(0xFF434c5e),
            shadowElevation = 5.dp
        ) {
            AsyncImage(
                model = metadata?.thumbnail ?: "",
                contentDescription = null,
                contentScale = ContentScale.Crop
            )
        }

        ButtonExample(
            modifier = Modifier.fillMaxWidth(),
            onClick = onCancel,
            text = "Return"
        )

    }
}

@Preview(showBackground = true, backgroundColor = 0xFF2b313c)
@Composable
fun loadingTest() {
    //Loading()
}

@Preview(showBackground = true, backgroundColor = 0xFF2b313c)
@Composable
fun downloadTest() {
    // uncomment for testing, otherwise keep them like that
    // Downloading()
}

@Preview(showBackground = true, backgroundColor = 0xFF2b313c)
@Composable
fun errorTest() {
    // Error()
}

