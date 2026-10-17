// One serial double-dabble converter shared by three numbers, one after the other:
//   a (11 bit, rpm)   -> ra: 4 BCD digits
//   b (7 bit, teeth)  -> rb: 2 BCD digits
//   c (7 bit, hours)  -> rc: 3 BCD digits
// Each conversion takes 12 clocks, so every result is refreshed about every 36 clocks.
`default_nettype none

module ip_bcd3 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [10:0] a,
    input  wire [6:0]  b,
    input  wire [6:0]  c,
    output reg  [15:0] ra,
    output reg  [7:0]  rb,
    output reg  [11:0] rc
);
    reg [1:0]  sel;
    reg [3:0]  cnt;
    reg [15:0] hi;
    reg [10:0] lo;

    // add 3 to every digit that is 5 or more
    wire [3:0] d3 = (hi[15:12] >= 4'd5) ? hi[15:12] + 4'd3 : hi[15:12];
    wire [3:0] d2 = (hi[11:8]  >= 4'd5) ? hi[11:8]  + 4'd3 : hi[11:8];
    wire [3:0] d1 = (hi[7:4]   >= 4'd5) ? hi[7:4]   + 4'd3 : hi[7:4];
    wire [3:0] d0 = (hi[3:0]   >= 4'd5) ? hi[3:0]   + 4'd3 : hi[3:0];

    wire [1:0]  nsel = (sel == 2'd2) ? 2'd0 : sel + 2'd1;
    wire [10:0] nxt  = (nsel == 2'd0) ? a : (nsel == 2'd1) ? {4'b0, b} : {4'b0, c};

    always @(posedge clk) begin
        if (!rst_n) begin
            sel <= 2'd0;
            cnt <= 4'd0;
            hi  <= 16'd0;
            lo  <= a;
            ra  <= 16'd0;
            rb  <= 8'd0;
            rc  <= 12'd0;
        end else if (cnt == 4'd11) begin
            if (sel == 2'd0)      ra <= hi;
            else if (sel == 2'd1) rb <= hi[7:0];
            else                  rc <= hi[11:0];
            sel <= nsel;
            hi  <= 16'd0;
            lo  <= nxt;
            cnt <= 4'd0;
        end else begin
            hi  <= {d3[2:0], d2, d1, d0, lo[10]};
            lo  <= {lo[9:0], 1'b0};
            cnt <= cnt + 4'd1;
        end
    end
endmodule
