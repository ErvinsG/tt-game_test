// Serial restoring divider: quo = num / den, truncated. Runs forever; a new result appears
// every NW+1 clocks. Inputs are latched at the start of each run so the result never glitches.
`default_nettype none

module ip_div #(
    parameter NW = 15,   // numerator width
    parameter DW = 6     // denominator width
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [NW-1:0] num,
    input  wire [DW-1:0] den,
    output reg  [NW-1:0] quo
);
    reg [NW-1:0] n, q;
    reg [DW-1:0] d;
    reg [DW:0]   r;
    reg [4:0]    cnt;

    wire [DW:0] rs = {r[DW-1:0], n[NW-1]};   // remainder shifted in one numerator bit

    always @(posedge clk) begin
        if (!rst_n) begin
            n <= num; d <= den; r <= 0; q <= 0; cnt <= NW; quo <= 0;
        end else if (cnt == 0) begin
            quo <= q;
            n <= num; d <= den; r <= 0; q <= 0; cnt <= NW;
        end else begin
            if (rs >= {1'b0, d}) begin
                r <= rs - {1'b0, d};
                q <= {q[NW-2:0], 1'b1};
            end else begin
                r <= rs;
                q <= {q[NW-2:0], 1'b0};
            end
            n   <= n << 1;
            cnt <= cnt - 5'd1;
        end
    end
endmodule
