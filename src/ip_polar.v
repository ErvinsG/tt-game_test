// Cartesian -> polar for the gear drawing, a pipelined CORDIC (vectoring mode, 8 iterations).
//
//   in : dx, dy  = pixel offset from the gear centre, 11 bit two's complement
//   out: rk      = radius * 1.6468   (the CORDIC gain; compare against thresholds scaled the same way)
//        th      = angle, 12 bit, 4096 = one full turn (screen coordinates, y down)
//        far     = offset too big (|dx| or |dy| >= 256), rk / th are meaningless
//
// Latency is LAT = 9 clocks (one input register + 8 iterations). The caller feeds the pixel
// that will be on screen LAT clocks later, i.e. x + 9, so the result lines up with the beam.
`default_nettype none

module ip_cordic_stage #(
    parameter I = 0,
    parameter [11:0] A = 12'd0       // atan(2^-I) in 1/4096 turns
) (
    input  wire        clk,
    input  wire [10:0] xi,           // unsigned
    input  wire [10:0] yi,           // two's complement
    input  wire [11:0] zi,
    output reg  [10:0] xo,
    output reg  [10:0] yo,
    output reg  [11:0] zo
);
    // arithmetic shift right of yi by I, spelled out with plain logic shifts (no >>> / $signed)
    wire [10:0] yfill = yi[10] ? ~(11'h7FF >> I) : 11'd0;
    wire [10:0] ysh   = (yi >> I) | yfill;
    wire [10:0] xsh = xi >> I;

    always @(posedge clk) begin
        if (!yi[10]) begin
            xo <= xi + ysh;
            yo <= yi - xsh;
            zo <= zi + A;
        end else begin
            xo <= xi - ysh;
            yo <= yi + xsh;
            zo <= zi - A;
        end
    end
endmodule

module ip_polar (
    input  wire        clk,
    input  wire [10:0] dx,
    input  wire [10:0] dy,
    output wire [10:0] rk,
    output reg  [11:0] th,
    output wire        far
);
    // |dx|, |dy| and the quadrant
    wire [10:0] ax = dx[10] ? (11'd0 - dx) : dx;
    wire [10:0] ay = dy[10] ? (11'd0 - dy) : dy;
    wire        far_c = (ax[10:8] != 3'd0) || (ay[10:8] != 3'd0);

    reg [10:0] x0, y0;
    reg [8:0]  sxp, syp, farp;      // quadrant and far flag travel down the pipeline

    always @(posedge clk) begin
        x0   <= {2'b00, ax[8:0]};
        y0   <= {2'b00, ay[8:0]};
        sxp  <= {sxp[7:0], dx[10]};
        syp  <= {syp[7:0], dy[10]};
        farp <= {farp[7:0], far_c};
    end

    wire [10:0] x1, y1, x2, y2, x3, y3, x4, y4, x5, y5, x6, y6, x7, y7, x8, y8;
    wire [11:0] z1, z2, z3, z4, z5, z6, z7, z8;

    ip_cordic_stage #(.I(0), .A(12'd512)) s0 (.clk(clk), .xi(x0), .yi(y0), .zi(12'd0), .xo(x1), .yo(y1), .zo(z1));
    ip_cordic_stage #(.I(1), .A(12'd302)) s1 (.clk(clk), .xi(x1), .yi(y1), .zi(z1),    .xo(x2), .yo(y2), .zo(z2));
    ip_cordic_stage #(.I(2), .A(12'd160)) s2 (.clk(clk), .xi(x2), .yi(y2), .zi(z2),    .xo(x3), .yo(y3), .zo(z3));
    ip_cordic_stage #(.I(3), .A(12'd81))  s3 (.clk(clk), .xi(x3), .yi(y3), .zi(z3),    .xo(x4), .yo(y4), .zo(z4));
    ip_cordic_stage #(.I(4), .A(12'd41))  s4 (.clk(clk), .xi(x4), .yi(y4), .zi(z4),    .xo(x5), .yo(y5), .zo(z5));
    ip_cordic_stage #(.I(5), .A(12'd20))  s5 (.clk(clk), .xi(x5), .yi(y5), .zi(z5),    .xo(x6), .yo(y6), .zo(z6));
    ip_cordic_stage #(.I(6), .A(12'd10))  s6 (.clk(clk), .xi(x6), .yi(y6), .zi(z6),    .xo(x7), .yo(y7), .zo(z7));
    ip_cordic_stage #(.I(7), .A(12'd5))   s7 (.clk(clk), .xi(x7), .yi(y7), .zi(z7),    .xo(x8), .yo(y8), .zo(z8));

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
