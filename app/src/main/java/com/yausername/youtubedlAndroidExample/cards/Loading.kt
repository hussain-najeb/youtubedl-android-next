package com.yausername.youtubedlAndroidExample.cards

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.material3.LoadingIndicator
import androidx.compose.ui.tooling.preview.Preview
import com.yausername.youtubeDLAndroidExampleCore.DownMetadata

@Composable
fun Loading(
  //  onCancel: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(10.dp)
    ) {
        Surface(
            shape = RoundedCornerShape(8.dp),
            shadowElevation = 5.dp,
        ) {
            Box(
                modifier = Modifier.fillMaxWidth().padding(24.dp),
                contentAlignment = Alignment.Center
            ) {
                LoadingIndicator(modifier = Modifier.size(60.dp))
            }
        }
    }
}

@Preview
@Composable
fun loadingTest() {
    Loading()
}


@Composable
fun Finished(
    metadata: DownMetadata,
    progress: Float,
    onCancel: () -> Unit
) {

}

@Composable
fun Error(
    error: String,
    onCancel: () -> Unit
) {

}