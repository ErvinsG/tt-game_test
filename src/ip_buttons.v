// Button debounce with no timer of its own: the button is sampled once per picture (tick = frame, 60 Hz)
// and the output only follows it when two samples in a row agree, so a bounce shorter than ~17 ms is ignored.
// The first flip-flop is the synchroniser for the asynchronous button input.
`default_nettype none

module ip_btn (
    input  wire clk,
    input  wire rst_n,
    input  wire tick,
    input  wire raw,
    output reg  clean
);
    reg s1, s2;
    always @(posedge clk) begin
        if (!rst_n) begin
            s1    <= 1'b0;
            s2    <= 1'b0;
            clean <= 1'b0;
        end else begin
            s1 <= raw;
            if (tick) begin
                s2 <= s1;
                if (s1 == s2) clean <= s1;
            end
        end
    end
endmodule
