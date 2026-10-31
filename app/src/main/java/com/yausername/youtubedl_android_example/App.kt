package com.yausername.youtubedl_android_example

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

@Composable
fun MainApp() {

    Column(modifier = Modifier
        .fillMaxSize()
        .background(color = Color(0xFF293141))
    ) {

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(10.dp)
                .weight(1f)
        ) {

        }

        Box(
            modifier = Modifier
                .padding(10.dp)
                .weight(1f)
        ) {
            TextField(
                value = ,

            )

        }
    }
}