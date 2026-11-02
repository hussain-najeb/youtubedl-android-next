package org.foss.youtube.next.example.ui.button

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp


@Composable
fun ButtonExample(
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    text: String
) {

    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()

    val animation by animateFloatAsState(
        targetValue = if (pressed) 0.90f else 1.0f,
        animationSpec = tween()
    )

    val container by animateColorAsState(
        targetValue = if (pressed) Color(0xFF719395) else Color(0xFF434c5e),
        animationSpec = tween(200)
    )
    val textColor by animateColorAsState(
        targetValue = if (pressed) Color(0xFF2e3440) else Color.White
    )

    Button(
        modifier = modifier
            .graphicsLayer {
                scaleX = animation
                scaleY = animation
            },
        onClick = onClick,
        shape = RoundedCornerShape(8.dp),
        elevation = ButtonDefaults.buttonElevation(
            pressedElevation = 4.dp,
            defaultElevation = 6.dp
        ),
        interactionSource = interactionSource,
        colors = ButtonDefaults.textButtonColors(
            containerColor = container,
            contentColor = textColor
        ),
    ) {
        Text(
            text = text
        )
    }
}