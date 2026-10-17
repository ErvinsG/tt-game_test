// Is the pixel (x, y) inside the rectangle that starts at (rx, ry) and is rw wide and rh high?
`default_nettype none

module ip_rect (
    input  wire [9:0] x,
    input  wire [9:0] y,
    input  wire [9:0] rx,
    input  wire [9:0] ry,
    input  wire [9:0] rw,
    input  wire [9:0] rh,
    output wire       hit
);
    assign hit = (x >= rx) && (x < rx + rw) && (y >= ry) && (y < ry + rh);
endmodule
