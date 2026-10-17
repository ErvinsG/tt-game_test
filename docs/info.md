## How it works

A VGA timing block says which pixel is being drawn. A paddle position register moves left or right once per picture, and a ball block bounces off the walls and the paddle. Two rectangle comparators decide whether the pixel being drawn is inside the paddle or the ball, and that picks the colour. Both buttons are synchronised and debounced.

## How to test

Connect a TinyVGA PMOD and a monitor, run the clock at 25.175 MHz, and press the two buttons to move the paddle.

## External hardware

TinyVGA PMOD and a VGA monitor, two push buttons.
