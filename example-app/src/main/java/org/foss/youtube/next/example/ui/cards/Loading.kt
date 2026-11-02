package org.foss.youtube.next.example.ui.cards

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.tooling.preview.Preview
import org.foss.youtube.next.example.DownMetadata
import org.foss.youtube.next.example.ui.button.ButtonExample

@Composable
fun Loading(
    // onCancel: () -> Unit
) {


    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(10.dp)
    ) {
        Surface(
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
                onClick = {},
                text = "Cancel"
            )
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF2b313c)
@Composable
fun loadingTest() {
    Loading()
}



@Composable
fun Downloading(
    metadata: DownMetadata,
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
        ) {
            AsyncImage

        }
    }
}

@Composable
fun Error(
    error: String,
    onCancel: () -> Unit
) {

}