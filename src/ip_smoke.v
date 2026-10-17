// A column of smoke above a source point (xs, ys): five puffs, each living 128 pictures.
// A puff rises about 0.75 px per picture (up to ~94 px), wobbles sideways, grows (half-size 4..11) and darkens with age.
// t is the picture counter (the caller adds a phase so two columns do not move in step).
`default_nettype none

module ip_smoke (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [10:0] xs,
    input  wire [10:0] ys,
    input  wire [6:0]  t,
    output wire        any,
    output wire        young       // the puff that was hit is in the first half of its life
);
    wire [6:0] a0 = t;
    wire [6:0] a1 = t + 7'd26;
    wire [6:0] a2 = t + 7'd51;
    wire [6:0] a3 = t + 7'd77;
    wire [6:0] a4 = t + 7'd102;

    wire [3:0] w0 = a0[4] ? ~a0[3:0] : a0[3:0];          // triangle wave 0..15 = the wobble
    wire [3:0] w1 = a1[4] ? ~a1[3:0] : a1[3:0];
    wire [3:0] w2 = a2[4] ? ~a2[3:0] : a2[3:0];
    wire [3:0] w3 = a3[4] ? ~a3[3:0] : a3[3:0];
    wire [3:0] w4 = a4[4] ? ~a4[3:0] : a4[3:0];

    wire [10:0] x0 = xs - 11'd14 + {7'b0, w0};
    wire [10:0] x1 = xs -  11'd2 + {7'b0, w1};
    wire [10:0] x2 = xs - 11'd10 + {7'b0, w2};
    wire [10:0] x3 = xs +  11'd2 + {7'b0, w3};
    wire [10:0] x4 = xs -  11'd6 + {7'b0, w4};
    wire [10:0] y0 = ys - {5'b0, a0[6:1]} - {6'b0, a0[6:2]};
    wire [10:0] y1 = ys - {5'b0, a1[6:1]} - {6'b0, a1[6:2]};
    wire [10:0] y2 = ys - {5'b0, a2[6:1]} - {6'b0, a2[6:2]};
    wire [10:0] y3 = ys - {5'b0, a3[6:1]} - {6'b0, a3[6:2]};
    wire [10:0] y4 = ys - {5'b0, a4[6:1]} - {6'b0, a4[6:2]};

    wire p0, p1, p2, p3, p4;
    ip_puff u0 (.x(x), .y(y), .xc(x0), .yc(y0), .hs({1'b0, a0[6:4]} + 4'd4), .hit(p0));
    ip_puff u1 (.x(x), .y(y), .xc(x1), .yc(y1), .hs({1'b0, a1[6:4]} + 4'd4), .hit(p1));
    ip_puff u2 (.x(x), .y(y), .xc(x2), .yc(y2), .hs({1'b0, a2[6:4]} + 4'd4), .hit(p2));
    ip_puff u3 (.x(x), .y(y), .xc(x3), .yc(y3), .hs({1'b0, a3[6:4]} + 4'd4), .hit(p3));
    ip_puff u4 (.x(x), .y(y), .xc(x4), .yc(y4), .hs({1'b0, a4[6:4]} + 4'd4), .hit(p4));

    assign any   = p0 || p1 || p2 || p3 || p4;
    assign young = (p0 && !a0[6]) || (p1 && !a1[6]) || (p2 && !a2[6]) || (p3 && !a3[6]) || (p4 && !a4[6]);
endmodule
