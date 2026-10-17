// One serial double-dabble converter shared by three numbers, one after the other (all 7 bit):
//   a -> ra: 2 BCD digits   (the rpm tens and hundreds: rpm = 100*a + 0/25/50/75, a <= 20)
//   b -> rb: 2 BCD digits   (teeth, 12..64)
//   c -> rc: 3 BCD digits   (gearbox hours, 0..100)
// Each conversion takes 8 clocks, so every result is refreshed about every 24 clocks.
`default_nettype none

module ip_bcd3 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [6:0]  a,
    input  wire [6:0]  b,
    input  wire [6:0]  c,
    output reg  [7:0]  ra,
    output reg  [7:0]  rb,
    output reg  [11:0] rc
);
    reg [1:0]  sel;
    reg [2:0]  cnt;
    reg [11:0] hi;
    reg [6:0]  lo;

    // add 3 to every digit that is 5 or more
    wire [3:0] d2 = (hi[11:8] >= 4'd5) ? hi[11:8] + 4'd3 : hi[11:8];
    wire [3:0] d1 = (hi[7:4]  >= 4'd5) ? hi[7:4]  + 4'd3 : hi[7:4];
    wire [3:0] d0 = (hi[3:0]  >= 4'd5) ? hi[3:0]  + 4'd3 : hi[3:0];

    wire [1:0] nsel = (sel == 2'd2) ? 2'd0 : sel + 2'd1;
    wire [6:0] nxt  = (nsel == 2'd0) ? a : (nsel == 2'd1) ? b : c;

    always @(posedge clk) begin
        if (!rst_n) begin
            sel <= 2'd0;
            cnt <= 3'd0;
            hi  <= 12'd0;
            lo  <= a;
            ra  <= 8'd0;
            rb  <= 8'd0;
            rc  <= 12'd0;
        end else if (cnt == 3'd7) begin
            if (sel == 2'd0)      ra <= hi[7:0];
            else if (sel == 2'd1) rb <= hi[7:0];
            else                  rc <= hi;
            sel <= nsel;
            hi  <= 12'd0;
            lo  <= nxt;
            cnt <= 3'd0;
        end else begin
            hi  <= {d2[2:0], d1, d0, lo[6]};
            lo  <= {lo[5:0], 1'b0};
            cnt <= cnt + 3'd1;
        end
    end
endmodule
