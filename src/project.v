// Grid chase, top module for the Tiny Tapeout game track. VGA timing comes from vga_shell.v, the game from game_core.v.
// Buttons: ui_in[0] left, ui_in[1] right, ui_in[2] up, ui_in[3] down.
// Optional Gamepad Pmod on ui_in[4] (latch), ui_in[5] (clock), ui_in[6] (data): its direction buttons work too.
`default_nettype none

module tt_um_ervinsg_game_test (
    input  wire [7:0] ui_in,    // dedicated inputs
    output wire [7:0] uo_out,   // dedicated outputs
    input  wire [7:0] uio_in,   // bidirectional pins, input path
    output wire [7:0] uio_out,  // bidirectional pins, output path
    output wire [7:0] uio_oe,   // bidirectional pins, 1 = drive
    input  wire       ena,      // high when the design is powered, ignore
    input  wire       clk,      // clock
    input  wire       rst_n     // reset, active low
);
    wire        hsync, vsync, active, frame;
    wire [9:0]  x, y;
    wire [5:0]  rgb;
    wire        gp_left, gp_right, gp_up, gp_down;     // directions from the Gamepad Pmod

    vga_sync vga (.clk(clk), .rst_n(rst_n), .hsync(hsync), .vsync(vsync), .active(active), .x(x), .y(y), .frame(frame));

    ip_gamepad pad (.clk(clk), .rst_n(rst_n), .latch(ui_in[4]), .pclk(ui_in[5]), .data(ui_in[6]),
                    .left(gp_left), .right(gp_right), .up(gp_up), .down(gp_down));

    game_core core (
        .clk(clk), .rst_n(rst_n),
        .left(ui_in[0] | gp_left), .right(ui_in[1] | gp_right),
        .up(ui_in[2] | gp_up),     .down(ui_in[3] | gp_down),
        .x(x), .y(y), .active(active), .frame(frame),
        .rgb(rgb)
    );

    // TinyVGA PMOD pin order: {hsync, B0, G0, R0, vsync, B1, G1, R1}
    assign uo_out = {hsync, rgb[0], rgb[2], rgb[4], vsync, rgb[1], rgb[3], rgb[5]};
    assign uio_out = 8'd0;
    assign uio_oe  = 8'd0;

    wire _unused = &{ena, uio_in, ui_in[7], 1'b0};
endmodule
