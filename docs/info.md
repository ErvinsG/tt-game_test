## How it works

A 20 x 20 field is drawn on a 640 x 480 VGA picture (cells of 32 x 24 pixels). You steer a dark green square, a yellow square walks around at random, and when the two meet the game is over and their cell turns dark blue.

* **VGA timing** gives the pixel position. The column of a cell is just the top bits of x; the row is counted line by line (24 lines per row), which is cheaper than dividing y by 24.
* **You** move one cell on every game tick (8 pictures, about 7.5 moves per second) while a direction pin is held. Two pins at once move diagonally. The square stops at the border.
* **The random square** moves on every 3rd game tick, one cell in a direction picked by a 16 bit LFSR.
* Both squares are 0.8 of a cell (26 x 20 pixels), so they stay inside their cell.
* **Game over:** when both squares are in the same cell the game stops. That cell turns dark blue (shown around a square that is half green, half yellow) and neither square moves any more. Reset starts a new game. Because the game ends at the first meeting, only one tile has to be remembered: the cell where the squares stopped.
* The four buttons are synchronised and sampled once per picture; a press counts when two samples in a row agree.
* **Gamepad Pmod (optional):** the direction buttons of controller 1 work as well. The Pmod sends a serial burst on three input pins (latch ui[4], clock ui[5], data ui[6]); the design picks the Up, Down, Left and Right bits out of it and ORs them with the plain buttons. An unplugged controller reads as all ones and is ignored.

## How to test

Connect a TinyVGA PMOD and a monitor, run the clock at 25.175 MHz and press the direction buttons: ui[0] left, ui[1] right, ui[2] up, ui[3] down. Or plug in a Gamepad Pmod on the input header and use the D-pad. Reset starts a new game with you in column 3 and the random square in column 16, both in row 10. When the two squares meet, the game stops until the next reset.

## External hardware

TinyVGA PMOD and a VGA monitor, and either four push buttons or a Gamepad Pmod with an SNES style controller.
