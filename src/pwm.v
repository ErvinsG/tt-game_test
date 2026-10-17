// PWM output: high while the free-running counter is below duty.
// The counter advances once every PRE clocks, so the PWM frequency is clk / (PRE * 256).
// 25 MHz / (8 * 256) = ~12 kHz.
`default_nettype none

module pwm #(
    parameter PRE = 8
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] duty,
    output reg        pwm_out
);
    reg [7:0] counter;
    reg [3:0] pre;

    always @(posedge clk) begin
        if (!rst_n) begin
            counter <= 8'd0;
            pre     <= 4'd0;
            pwm_out <= 1'b0;
        end else begin
            if (pre == PRE - 1) begin
                pre     <= 4'd0;
                counter <= counter + 8'd1;
            end else begin
                pre <= pre + 4'd1;
            end
            pwm_out <= (counter < duty);
        end
    end
endmodule
