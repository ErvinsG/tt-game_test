// Serial double-dabble: turns an unsigned W bit number into 4 BCD digits (digit 0 = lowest nibble).
// Runs forever; a fresh result is latched every W+1 clocks.
// Written without generate / indexed part-selects so simple Verilog parsers accept it.
`default_nettype none

module ip_bin2bcd #(
    parameter W = 11
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [W-1:0] bin,
    output reg  [15:0]  bcd
);
    reg [15:0]  hi;     // the BCD digits being built
    reg [W-1:0] lo;     // the bits still to shift in
    reg [4:0]   cnt;

    // add 3 to every digit that is 5 or more
    wire [3:0] d3 = (hi[15:12] >= 4'd5) ? hi[15:12] + 4'd3 : hi[15:12];
    wire [3:0] d2 = (hi[11:8]  >= 4'd5) ? hi[11:8]  + 4'd3 : hi[11:8];
    wire [3:0] d1 = (hi[7:4]   >= 4'd5) ? hi[7:4]   + 4'd3 : hi[7:4];
    wire [3:0] d0 = (hi[3:0]   >= 4'd5) ? hi[3:0]   + 4'd3 : hi[3:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            hi  <= 16'd0;
            lo  <= bin;
            cnt <= 5'd0;
            bcd <= 16'd0;
        end else if (cnt == W) begin
            bcd <= hi;
            hi  <= 16'd0;
            lo  <= bin;
            cnt <= 5'd0;
        end else begin
            hi  <= {d2, d1, d0, lo[W-1]};
            lo  <= {lo[W-2:0], 1'b0};
            cnt <= cnt + 5'd1;
        end
    end
endmodule
