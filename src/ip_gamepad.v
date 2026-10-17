// Reads the direction buttons of controller 1 from the Tiny Tapeout Gamepad Pmod (psychogenic/gamepad-pmod).
// A reduced version of the official gamepad_pmod_single (Copyright (c) 2025 Pat Deegan, psychogenic.com, Apache-2.0):
// same protocol and the same way of picking the bits, but only the four directions are kept.
//
// The Pmod drives three signals into the input pins: latch = ui_in[4], clock = ui_in[5], data = ui_in[6].
// It sends a burst of 12 bits per controller (24 bits for two, ~100 kHz, 1 = pressed) and pulses the latch
// after the last bit. Bit order of one controller:
//   B, Y, Select, Start, Up, Down, Left, Right, A, X, L, R
// Controller 1 is the LAST 12 bits before the latch pulse (a single controller sends only these 12 bits).
// So: every rising clock edge shifts the data bit into a 12 bit register, and on the rising edge of the latch
// the register holds controller 1: bit 7 = Up, 6 = Down, 5 = Left, 4 = Right, 3 = A (the buy button).
// All twelve bits high means "no controller connected": the directions then stay low.
//
// Each input goes through a two flip-flop synchroniser.
`default_nettype none

module ip_gamepad (
    input  wire clk,
    input  wire rst_n,
    input  wire latch,
    input  wire pclk,
    input  wire data,
    output reg  left,
    output reg  right,
    output reg  up,
    output reg  down,
    output reg  a
);
    reg [1:0]  ls, cs, ds;       // synchronisers
    reg        lp, cp;           // previous synchronised latch / clock, for edge detection
    reg [11:0] sh;               // the last 12 bits received

    always @(posedge clk) begin
        if (!rst_n) begin
            ls <= 2'b00; cs <= 2'b00; ds <= 2'b00;
            lp <= 1'b0;  cp <= 1'b0;
            sh <= 12'hFFF;                           // "no controller" until the first burst arrives
            up <= 1'b0;  down <= 1'b0;  left <= 1'b0;  right <= 1'b0;  a <= 1'b0;
        end else begin
            ls <= {ls[0], latch};
            cs <= {cs[0], pclk};
            ds <= {ds[0], data};
            lp <= ls[1];
            cp <= cs[1];
            if (cs[1] && !cp) sh <= {sh[10:0], ds[1]};      // rising clock edge: this data bit is valid
            if (ls[1] && !lp) begin                         // rising latch edge: the burst is complete
                up    <= !(&sh) && sh[7];
                down  <= !(&sh) && sh[6];
                left  <= !(&sh) && sh[5];
                right <= !(&sh) && sh[4];
                a     <= !(&sh) && sh[3];
            end
        end
    end
endmodule
