// Button debouncing for all buttons with ONE shared sample timer.
//
// ip_sample: one pulse every DIV clocks (DIV = 32768 -> 1.3 ms at 25 MHz).
// ip_btn1:   the button must read the same on 4 samples in a row before the output follows it,
//            so a bounce shorter than ~4 sample periods (5 ms) is ignored. The first flip-flop is the
//            synchroniser for the asynchronous button.
`default_nettype none

module ip_sample #(
    parameter DIV = 32768,
    parameter W   = 16
) (
    input  wire clk,
    input  wire rst_n,
    output wire tick
);
    reg [W-1:0] count;
    assign tick = (count == DIV - 1);
    always @(posedge clk) begin
        if (!rst_n || tick) count <= 0;
        else                count <= count + 1'b1;
    end
endmodule

module ip_btn1 (
    input  wire clk,
    input  wire rst_n,
    input  wire tick,
    input  wire raw,
    output reg  clean
);
    reg       sync;
    reg [3:0] hist;
    always @(posedge clk) begin
        if (!rst_n) begin
            sync  <= 1'b0;
            hist  <= 4'b0;
            clean <= 1'b0;
        end else begin
            sync <= raw;
            if (tick) begin
                hist <= {hist[2:0], sync};
                if (hist == 4'b1111)      clean <= 1'b1;
                else if (hist == 4'b0000) clean <= 1'b0;
            end
        end
    end
endmodule
