// A plume of smoke rising from a source point (xs, ys), made from cheap pseudo-random blocks.
//
// h = how far above the source the pixel is (0..95). The plume is a triangle that widens with h,
// and a block of 4x4 pixels is lit when a small hash of its position is below a threshold that
// falls with h, so the smoke is dense near the gear and thins out as it rises.
// The hash looks at (x, y + t), so the pattern scrolls upwards as the picture counter t grows.
`default_nettype none

module ip_plume (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [10:0] xs,
    input  wire [10:0] ys,
    input  wire [7:0]  t,
    output wire        on,
    output wire        young       // lower, denser part of the plume: drawn lighter
);
    wire [10:0] xe = {1'b0, x};
    wire [10:0] ye = {1'b0, y};

    wire        above = (ye < ys);
    wire [10:0] h11   = ys - ye;                      // height above the source (valid when above)
    wire        h_ok  = above && (h11 < 11'd96);
    wire [6:0]  h     = h11[6:0];

    wire [10:0] dxa   = (xe >= xs) ? (xe - xs) : (xs - xe);
    wire [6:0]  hw    = 7'd8 + {1'b0, h[6:1]};        // half width: 8 at the source, 55 at the top
    wire        in_tri = (dxa < {4'b0, hw});

    // block hash: 4 bit mix of the block column and the (scrolling) block row
    wire [5:0]  bx = xe[7:2];
    wire [5:0]  by = ye[7:2] + t[7:2];
    wire [3:0]  n  = bx[3:0] ^ {by[2:0], by[3]} ^ (bx[5:2] + by[5:2]) ^ {bx[1:0], by[1:0]};

    wire [3:0]  thr = (h[6:3] >= 4'd12) ? 4'd0 : (4'd12 - h[6:3]);   // 12 near the gear .. 1 at the top
    assign on    = h_ok && in_tri && (n < thr);
    assign young = (h < 7'd40);
endmodule
