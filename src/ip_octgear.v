// One gear, drawn as an octagon whose teeth are plain bars sliding along the perimeter.
// No angle, no CORDIC, no multiplier: everything is a few shifts and adds on the pixel offset.
//
// (dx, dy) = pixel offset from the gear centre. N teeth, tooth pitch 16 px along the perimeter, so the
// octagon has a half edge of N px and an inradius R = 2.414 N.
//   a = |dx|, b = |dy|.   The pixel is in an axis edge region when 12*min(a,b) <= 5*max(a,b)
//   (tan 22.5 deg ~ 5/12), otherwise in a diagonal region.
//   d = distance to the nearest edge line: max(a,b) in the axis regions, (a+b)*45/64 in the diagonal ones.
//   body: d < root,  tooth ring: d < tip and the tooth phase is inside the tooth.
// Tooth phase (mod 16 px) is the position along the perimeter: base(k) + term + rot, where k = which of the
// 8 edges and base(k) = (2k+1)*N mod 16. term is dy, dx or 45/64*(b-a) with a sign that depends on the edge.
// rot is the rotation of the gear in px (0..15).
`default_nettype none

module ip_octgear (
    input  wire [10:0] dx,
    input  wire [10:0] dy,
    input  wire [8:0]  root,     // body edge  (R - 4)
    input  wire [8:0]  tip,      // tooth tips (R + 2)
    input  wire [3:0]  n4,       // N mod 16
    input  wire [3:0]  rot,      // rotation phase, px
    output wire        hit
);
    wire sx = dx[10];
    wire sy = dy[10];
    // both offsets must be inside -255 .. 255, so an 8 bit magnitude is enough
    wire in_x = !(|dx[10:8]) || ((&dx[10:8]) && (|dx[7:0]));
    wire in_y = !(|dy[10:8]) || ((&dy[10:8]) && (|dy[7:0]));

    wire [7:0] a = sx ? (8'd0 - dx[7:0]) : dx[7:0];
    wire [7:0] b = sy ? (8'd0 - dy[7:0]) : dy[7:0];

    wire       a_ge_b = (a >= b);
    wire [7:0] hi = a_ge_b ? a : b;
    wire [7:0] lo = a_ge_b ? b : a;
    wire [11:0] lo12 = {1'b0, lo, 3'b000} + {2'b00, lo, 2'b00};     // 12 * lo
    wire [11:0] hi5  = {2'b00, hi, 2'b00} + {4'b0000, hi};          // 5 * hi
    wire axis = (lo12 <= hi5);
    wire xreg = axis && a_ge_b;
    wire yreg = axis && !a_ge_b;

    // diagonal distance (a+b)*45/64
    wire [8:0] sum = {1'b0, a} + {1'b0, b};
    wire [8:0] dd  = {1'b0, sum[8:1]} + {3'b000, sum[8:3]} + {4'b0000, sum[8:4]} + {6'b000000, sum[8:6]};
    wire [8:0] d   = axis ? {1'b0, hi} : dd;

    // diagonal phase term: (b-a)*45/64 mod 16
    wire [9:0] e    = {2'b00, b} - {2'b00, a};
    wire [9:0] prod = {e[4:0], 5'b00000} + {e[6:0], 3'b000} + {e[7:0], 2'b00} + e;
    wire [3:0] q    = prod[9:6];

    wire [3:0] term_raw = xreg ? dy[3:0] : yreg ? dx[3:0] : q;
    wire       neg      = xreg ? sx : yreg ? !sy : (sx != sy);
    wire [3:0] term     = neg ? (4'd0 - term_raw) : term_raw;

    // base(k) = (2k+1) * N mod 16; (2k+1) depends on the edge
    wire [3:0] m = xreg ? (sx ? 4'd9 : 4'd1) :
                   yreg ? (sy ? 4'd13 : 4'd5) :
                   (!sx && !sy) ? 4'd3 : (sx && !sy) ? 4'd7 : (sx && sy) ? 4'd11 : 4'd15;
    wire [7:0] mp   = m * n4;
    wire [3:0] base = mp[3:0];

    wire [3:0] ph    = base + term + rot;
    wire       tooth = (ph >= 4'd4) && (ph < 4'd9);

    assign hit = in_x && in_y && (d < tip) && ((d < root) || tooth);
endmodule
