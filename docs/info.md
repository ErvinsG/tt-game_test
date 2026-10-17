## How it works

A 20 x 20 field is drawn on a 640 x 480 VGA picture (cells of 32 x 24 pixels). You steer a dark green square and chase a yellow square that runs away from you. Only a 3 x 3 window around you is clear, the rest is fog. Every catch adds a golden line in the top left corner and sends the yellow square to a new place.

* **VGA timing** gives the pixel position. The column of a cell is just the top bits of x; the row is counted line by line (24 lines per row), which is cheaper than dividing y by 24.
* **You** move one cell on every game tick (8 pictures, about 7.5 moves per second) while a direction pin is held. Two pins at once move diagonally. The square stops at the border.
* **The yellow square runs away.** It moves on every 3rd game tick, one cell: along the axis where you are farther away from it, sliding along a wall when that way is blocked (in a corner it is stuck). In one move out of four it steps in a random direction instead, picked by a 16 bit LFSR, so it is not completely predictable. You move three times as often, so you can corner it.
* **Fog of war:** only a small window of cells around you is visible (you are in its middle cell; at the map edge the window stays on the map). The rest of the field is grey fog, so the yellow square can hide in it. Inside the window thin cell borders are drawn. The window starts at 3 x 3.
* **Coins and the fog upgrade:** every catch is a coin (the golden lines in the top left corner). Press the buy button (ui[7], or the A button of a Gamepad Pmod) with at least 4 coins to spend them on a bigger window: 3 x 3 becomes 5 x 5, and the next upgrade 7 x 7. A small cyan square under the golden lines shows each upgrade you have bought. At the top level the button does nothing and keeps your coins.
* Both squares are 0.8 of a cell (26 x 20 pixels), so they stay inside their cell.
* **Catching:** when both squares are in the same cell you have caught the yellow square. The catch counter goes up: one golden line per catch in the top left corner, up to 31. The cell of the latest catch turns dark blue. The yellow square then respawns on the other half of the field (at least 5 columns away, random row) and the chase goes on. Reset sets the counter back to zero.
* The five buttons are synchronised and sampled once per picture; a press counts when two samples in a row agree.
* **Gamepad Pmod (optional):** the direction buttons of controller 1 work as well. The Pmod sends a serial burst on three input pins (latch ui[4], clock ui[5], data ui[6]); the design picks the Up, Down, Left, Right and A bits out of it and ORs them with the plain buttons. An unplugged controller reads as all ones and is ignored.

## How to test

Connect a TinyVGA PMOD and a monitor, run the clock at 25.175 MHz and press the direction buttons: ui[0] left, ui[1] right, ui[2] up, ui[3] down, and ui[7] to buy a fog upgrade. Or plug in a Gamepad Pmod on the input header and use the D-pad. Reset starts with you in column 3 and the yellow square in column 16, both in row 10, and the catch counter at zero. Catch the yellow square as often as you can.

## External hardware

TinyVGA PMOD and a VGA monitor, and either five push buttons (four directions and buy) or a Gamepad Pmod with an SNES style controller (D-pad and A).
