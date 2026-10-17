// One round-ish smoke puff: an octagon of half-size hs centred on (xc, yc).
// Inside when |dx| < hs, |dy| < hs and |dx| + |dy| < 1.5 * hs (the square with its corners cut off).
`default_nettype none

module ip_puff (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [10:0] xc,
    input  wire [10:0] yc,
    input  wire [3:0]  hs,
    output wire        hit
);
    wire [10:0] xe  = {1'b0, x};
    wire [10:0] ye  = {1'b0, y};
    wire [10:0] dxa = (xe >= xc) ? (xe - xc) : (xc - xe);
    wire [10:0] dya = (ye >= yc) ? (ye - yc) : (yc - ye);
    wire [10:0] h   = {7'b0, hs};
    assign hit = (dxa < h) && (dya < h) && ((dxa + dya) < (h + {1'b0, h[10:1]}));
endmodule
