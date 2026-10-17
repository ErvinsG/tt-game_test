// Cartesian -> polar for the gear drawing, a pipelined CORDIC (vectoring mode, 8 iterations).
//
//   in : dx, dy  = pixel offset from the gear centre, 11 bit two's complement
//   out: rk      = radius * 1.6468   (the CORDIC gain; compare against thresholds scaled the same way)
//        th      = angle, 12 bit, 4096 = one full turn (screen coordinates, y down)
//        far     = offset outside +-2^M, rk / th are meaningless
//
// M sets the size of the datapath: offsets up to 2^M - 1 are handled with M+2 bit radius numbers.
// A small gear only needs a small M (gear 1: M = 6, gear 2: M = 7), which is what keeps the area down.
//
// Latency is LAT = 9 clocks (one input register + 8 iterations). The caller feeds the pixel
// that will be on screen LAT clocks later, i.e. x + 9, so the result lines up with the beam.
`default_nettype none

module ip_cordic_stage #(
    parameter I  = 0,
    parameter XW = 8,
    parameter YW = 9,
    parameter [11:0] A = 12'd0       // atan(2^-I) in 1/4096 turns
) (
    input  wire          clk,
    input  wire [XW-1:0] xi,         // unsigned
    input  wire [YW-1:0] yi,         // two's complement
    input  wire [11:0]   zi,
    output reg  [XW-1:0] xo,
    output reg  [YW-1:0] yo,
    output reg  [11:0]   zo
);
    // arithmetic shift right of yi by I, spelled out with plain logic shifts (no >>> / $signed)
    wire [YW-1:0] zero  = 0;
    wire [YW-1:0] ones  = ~zero;
    wire [YW-1:0] yfill = yi[YW-1] ? ~(ones >> I) : zero;
    wire [YW-1:0] ysh   = (yi >> I) | yfill;
    wire [XW-1:0] xsh   = xi >> I;
    wire [XW-1:0] ysx   = ysh[XW-1:0];          // |y| < 2^XW, so the low bits are the same number mod 2^XW
    wire [YW-1:0] xsy   = {1'b0, xsh};                  // YW = XW + 1

    always @(posedge clk) begin
        if (!yi[YW-1]) begin
            xo <= xi + ysx;
            yo <= yi - xsy;
            zo <= zi + A;
        end else begin
            xo <= xi - ysx;
            yo <= yi + xsy;
            zo <= zi - A;
        end
    end
endmodule

module ip_polar #(
    parameter M = 7
) (
    input  wire          clk,
    input  wire [10:0]   dx,
    input  wire [10:0]   dy,
    output wire [M+1:0]  rk,
    output reg  [11:0]   th,
    output wire          far
);
    localparam XW = M + 2;
    localparam YW = M + 3;

    // in range when dx, dy are in -2^M .. 2^M-1, i.e. every bit from 10 down to M is the sign
    wire dx_ok = (&dx[10:M]) || !(|dx[10:M]);
    wire dy_ok = (&dy[10:M]) || !(|dy[10:M]);

    // |dx|, |dy| and the quadrant, on M+1 bits
    wire [M:0] dxl = dx[M:0];
    wire [M:0] dyl = dy[M:0];
    wire [M:0] ax  = dx[10] ? (0 - dxl) : dxl;
    wire [M:0] ay  = dy[10] ? (0 - dyl) : dyl;
    wire far_c = !dx_ok || !dy_ok || ax[M] || ay[M];

    reg [XW-1:0] x0;
    reg [YW-1:0] y0;
    reg [8:0]    sxp, syp, farp;      // quadrant and far flag travel down the pipeline

    always @(posedge clk) begin
        x0   <= {2'b00,  ax[M-1:0]};
        y0   <= {3'b000, ay[M-1:0]};
        sxp  <= {sxp[7:0], dx[10]};
        syp  <= {syp[7:0], dy[10]};
        farp <= {farp[7:0], far_c};
    end

    wire [XW-1:0] x1, x2, x3, x4, x5, x6, x7, x8;
    wire [YW-1:0] y1, y2, y3, y4, y5, y6, y7, y8;
    wire [11:0]   z1, z2, z3, z4, z5, z6, z7, z8;

    ip_cordic_stage #(.I(0), .XW(XW), .YW(YW), .A(12'd512)) s0 (.clk(clk), .xi(x0), .yi(y0), .zi(12'd0), .xo(x1), .yo(y1), .zo(z1));
    ip_cordic_stage #(.I(1), .XW(XW), .YW(YW), .A(12'd302)) s1 (.clk(clk), .xi(x1), .yi(y1), .zi(z1),    .xo(x2), .yo(y2), .zo(z2));
    ip_cordic_stage #(.I(2), .XW(XW), .YW(YW), .A(12'd160)) s2 (.clk(clk), .xi(x2), .yi(y2), .zi(z2),    .xo(x3), .yo(y3), .zo(z3));
    ip_cordic_stage #(.I(3), .XW(XW), .YW(YW), .A(12'd81))  s3 (.clk(clk), .xi(x3), .yi(y3), .zi(z3),    .xo(x4), .yo(y4), .zo(z4));
    ip_cordic_stage #(.I(4), .XW(XW), .YW(YW), .A(12'd41))  s4 (.clk(clk), .xi(x4), .yi(y4), .zi(z4),    .xo(x5), .yo(y5), .zo(z5));
    ip_cordic_stage #(.I(5), .XW(XW), .YW(YW), .A(12'd20))  s5 (.clk(clk), .xi(x5), .yi(y5), .zi(z5),    .xo(x6), .yo(y6), .zo(z6));
    ip_cordic_stage #(.I(6), .XW(XW), .YW(YW), .A(12'd10))  s6 (.clk(clk), .xi(x6), .yi(y6), .zi(z6),    .xo(x7), .yo(y7), .zo(z7));
    ip_cordic_stage #(.I(7), .XW(XW), .YW(YW), .A(12'd5))   s7 (.clk(clk), .xi(x7), .yi(y7), .zi(z7),    .xo(x8), .yo(y8), .zo(z8));

    assign rk  = x8;
    assign far = farp[8];

    // fold the first-quadrant angle back into the right quadrant
    always @(*) begin
        if (!sxp[8] && !syp[8])      th = z8;
        else if (sxp[8] && !syp[8])  th = 12'd2048 - z8;
        else if (sxp[8] && syp[8])   th = 12'd2048 + z8;
        else                         th = 12'd0 - z8;
    end

    wire _unused = &{y8, 1'b0};
endmodule

// radius threshold * 1.6468 (the CORDIC gain), as shift-add: t * (1 + 1/2 + 1/8 + 1/64 + 1/128)
module ip_kmul (
    input  wire [8:0]  t,
    output wire [10:0] k
);
    assign k = {2'b0, t} + {3'b0, t[8:1]} + {5'b0, t[8:3]} + {8'b0, t[8:6]} + {9'b0, t[8:7]};
endmodule
