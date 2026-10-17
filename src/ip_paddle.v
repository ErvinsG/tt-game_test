// A paddle position: moves STEP pixels left or right on each step pulse, and stops at the edges.
`default_nettype none

module ip_paddle #(
    parameter MAX  = 576,
    parameter STEP = 4
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       step,
    input  wire       left,
    input  wire       right,
    output reg  [9:0] pos
);
    always @(posedge clk) begin
        if (!rst_n) begin
            pos <= MAX / 2;
        end else if (step) begin
            if (left && !right) begin
                if (pos < STEP) pos <= 10'd0;
                else            pos <= pos - STEP;
            end else if (right && !left) begin
                if (pos + STEP > MAX) pos <= MAX;
                else                  pos <= pos + STEP;
            end
        end
    end
endmodule
