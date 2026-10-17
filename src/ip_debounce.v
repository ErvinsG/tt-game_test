// Synchronises a noisy input and only changes the output when the input has held steady for N clocks.
`default_nettype none

module ip_debounce #(
    parameter N = 16
) (
    input  wire clk,
    input  wire rst_n,
    input  wire noisy,
    output reg  clean
);
    reg        sync1, sync2;
    reg [19:0] count;

    always @(posedge clk) begin
        if (!rst_n) begin
            sync1 <= 1'b0;
            sync2 <= 1'b0;
            count <= 20'd0;
            clean <= 1'b0;
        end else begin
            sync1 <= noisy;
            sync2 <= sync1;
            if (sync2 == clean) begin
                count <= 20'd0;
            end else if (count == N - 1) begin
                clean <= sync2;
                count <= 20'd0;
            end else begin
                count <= count + 20'd1;
            end
        end
    end
endmodule
