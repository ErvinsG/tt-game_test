// Single-file bundle of src/ for pasting into vga-playground. Generated - edit src/, not this.
// ===== project.v =====
// The Tiny Tapeout top module for the game track (the shell). It is given and you do not edit it.
// It makes the VGA timing and hands your core the pixel position, the buttons and a once per
// picture pulse. Your core gives back one colour. Buttons: ui_in[0] left, ui_in[1] right.

module tt_um_vga_example (
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
    wire        pwm_out;

    vga_sync vga (.clk(clk), .rst_n(rst_n), .hsync(hsync), .vsync(vsync), .active(active), .x(x), .y(y), .frame(frame));

    game_core core (
        .clk(clk), .rst_n(rst_n),
        .left(ui_in[0]), .right(ui_in[1]),
        .up(ui_in[2]),   .down(ui_in[3]),
        .clutch(ui_in[4]),
        .x(x), .y(y), .active(active), .frame(frame),
        .rgb(rgb), .pwm_out(pwm_out)
    );

    // TinyVGA PMOD pin order: {hsync, B0, G0, R0, vsync, B1, G1, R1}
    assign uo_out = {hsync, rgb[0], rgb[2], rgb[4], vsync, rgb[1], rgb[3], rgb[5]};
    // uio[0] = motor PWM
    assign uio_out = {7'd0, pwm_out};
    assign uio_oe  = 8'b0000_0001;

    wire _unused = &{ena, uio_in, ui_in[7:5], 1'b0};
endmodule

// ===== game_core.v =====
// Gear ratio demo: parameters, rpm2, PWM, text and two meshing gears on screen.
//
// Oil: at 5 h or less the lamp blinks and the clutch (Select) adds oil (drips into the mesh, counter back to 100 h).
// At 0 h it is GAME OVER: motor forced to 0 rpm, controls locked, smoke rises from the gears; only reset restarts.
//   P1 = motor speed, index 0..80 -> 0..2000 rpm in steps of 25
//   P2 = teeth of gear 2, 12..64
//   rpm2 = rpm1 * 12 / P2
//
// Buttons: left selects P1, right selects P2, up/down change the selected one.
// Select = clutch: the tooth count (P2) can only be changed while the clutch is held or the motor is at 0 rpm.
// Oil: a 100 h gearbox counter runs down while the motor turns; at 0 an oil can lamp blinks in the top
// right corner. Press the clutch (Select) and oil drips into the gear mesh, then the counter is back to 100 h.
// Screen: 20 x 15 text cells of 32 x 32 pixels (a 5x7 glyph drawn at 4x scale).

module game_core #(
    parameter DB   = 500000,     // debounce time in clocks, 20 ms at 25 MHzs
    parameter STEP = 4,          // change a value every STEP pictures while up/down is held
    parameter HFRAMES = 36       // pictures per gearbox hour: 100 h x 36 / 60 Hz = 1 minutes of running
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        left,      // raw buttons, they bounce
    input  wire        right,
    input  wire        up,
    input  wire        down,
    input  wire        clutch,    // Select button, raw
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire        active,
    input  wire        frame,
    output wire [5:0]  rgb,       // {R[1:0], G[1:0], B[1:0]}
    output wire        pwm_out
);
    // ------------------------------------------------------------------
    // 1. buttons
    // ------------------------------------------------------------------
    wire left_c, right_c, up_c, down_c, clutch_c;
    ip_debounce #(.N(DB)) db_left  (.clk(clk), .rst_n(rst_n), .noisy(left),  .clean(left_c));
    ip_debounce #(.N(DB)) db_right (.clk(clk), .rst_n(rst_n), .noisy(right), .clean(right_c));
    ip_debounce #(.N(DB)) db_up    (.clk(clk), .rst_n(rst_n), .noisy(up),    .clean(up_c));
    ip_debounce #(.N(DB)) db_down  (.clk(clk), .rst_n(rst_n), .noisy(down),  .clean(down_c));
    ip_debounce #(.N(DB)) db_clutch(.clk(clk), .rst_n(rst_n), .noisy(clutch),.clean(clutch_c));

    reg [6:0] hours;          // gearbox working hours left, 100 .. 0
    wire      oil_low  = (hours == 7'd0);                  // GAME OVER: motor forced to 0 rpm, only reset restarts
    wire      oil_warn = (hours <= 7'd5) && !oil_low;      // 5 h or less: lamp blinks, the clutch can add oil

    wire step;
    ip_tick #(.DIV(STEP)) step_tick (.clk(clk), .rst_n(rst_n), .en(frame), .tick(step));

    // ------------------------------------------------------------------
    // 2. parameters
    // ------------------------------------------------------------------
    reg       sel;            // 0 = editing P1, 1 = editing P2
    reg [6:0] p1;             // rpm / 25, 0..80
    reg [6:0] p2;             // teeth, 12..64 (7 bits: 64 does not fit in 6)

    // the gears can only be swapped when they are not driven (0 rpm) or the clutch is pressed
    wire can_shift = (clutch_c || (p1 == 7'd0)) && !oil_low;

    // a press acts at once (rising edge); holding the button for a few steps then repeats every STEP pictures
    reg       up_d, down_d;
    reg [1:0] hold;
    always @(posedge clk) begin
        up_d   <= up_c;
        down_d <= down_c;
        if (!up_c && !down_c)          hold <= 2'd0;
        else if (step && hold != 2'd3) hold <= hold + 2'd1;
    end
    wire up_rise   = up_c   && !up_d;
    wire down_rise = down_c && !down_d;
    wire repeat_ok = step && (hold == 2'd3);

    always @(posedge clk) begin
        if (!rst_n) begin
            sel <= 1'b0;
            p1  <= 7'd40;     // 1000 rpm
            p2  <= 7'd12;
        end else begin
            if (left_c && !right_c)      sel <= 1'b0;
            else if (right_c && !left_c) sel <= 1'b1;

            if (repeat_ok || up_rise || down_rise) begin
                if (!sel) begin
                    if (oil_low) ;                       // game over: P1 stays locked at 0
                    else if (up_c && !down_c) p1 <= (p1 < 7'd80) ? p1 + 7'd1 : p1;
                    else if (down_c && !up_c) p1 <= (p1 > 7'd0)  ? p1 - 7'd1 : p1;
                end else if (can_shift) begin
                    if (up_c && !down_c)      p2 <= (p2 < 7'd64) ? p2 + 7'd1 : p2;
                    else if (down_c && !up_c) p2 <= (p2 > 7'd12) ? p2 - 7'd1 : p2;
                end
            end

            if (oil_low) p1 <= 7'd0;             // the gearbox seized: motor speed forced to 0 rpm
        end
    end

    // rpm1 = p1 * 25
    wire [10:0] rpm1 = {p1, 4'b0} + {p1, 3'b0} + p1;

    // rpm2 = rpm1 * 12 / p2 = p1 * 300 / p2
    wire [14:0] num2 = {p1, 8'b0} + {p1, 5'b0} + {p1, 3'b0} + {p1, 2'b0};
    wire [14:0] rpm2_w;
    ip_div #(.NW(15), .DW(7)) u_div (.clk(clk), .rst_n(rst_n), .num(num2), .den(p2), .quo(rpm2_w));
    wire [10:0] rpm2 = rpm2_w[10:0];

    // ------------------------------------------------------------------
    // 3. PWM: duty = rpm1 / 2000 * 255 = p1 * 3.1875 (p1 = 80 -> 255)
    // ------------------------------------------------------------------
    wire [7:0] duty = {p1, 1'b0} + p1 + {3'b0, p1[6:3]} + {4'b0, p1[6:4]};
    pwm #(.PRE(8)) u_pwm (.clk(clk), .rst_n(rst_n), .duty(duty), .pwm_out(pwm_out));

    // ------------------------------------------------------------------
    // 3b. gearbox oil: hours left, the lamp and the refill animation
    // ------------------------------------------------------------------
    localparam [7:0] REFILL_FRAMES = 8'd150;     // about 2.5 s of dripping

    reg       refill;         // oil is being added
    reg [7:0] oil_t;          // pictures since the refill started
    reg [7:0] fcount;         // free running picture counter (lamp blink, smoke)
    reg       clutch_d;

    wire running = (p1 != 7'd0);
    wire hour_tick;
    ip_tick #(.DIV(HFRAMES)) u_htick (.clk(clk), .rst_n(rst_n),
        .en(frame && running && !refill && !oil_low), .tick(hour_tick));

    wire clutch_rise = clutch_c && !clutch_d;

    always @(posedge clk) begin
        clutch_d <= clutch_c;
        if (!rst_n) begin
            hours  <= 7'd12;
            refill <= 1'b0;
            oil_t  <= 8'd0;
            fcount <= 8'd0;
        end else begin
            if (frame) fcount <= fcount + 8'd1;
            if (hour_tick) hours <= hours - 7'd1;

            if (clutch_rise && oil_warn && !refill) begin
                refill <= 1'b1;
                oil_t  <= 8'd0;
            end else if (refill && frame) begin
                if (oil_t == REFILL_FRAMES - 8'd1) begin
                    refill <= 1'b0;
                    hours  <= 7'd100;
                end else begin
                    oil_t <= oil_t + 8'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // 4. binary -> decimal digits
    // ------------------------------------------------------------------
    wire [15:0] bcd1, bcd2;
    wire [15:0] bcdt16;
    wire [7:0]  bcdt = bcdt16[7:0];
    ip_bin2bcd #(.W(11)) u_b1 (.clk(clk), .rst_n(rst_n), .bin(rpm1), .bcd(bcd1));
    ip_bin2bcd #(.W(11)) u_b2 (.clk(clk), .rst_n(rst_n), .bin(rpm2), .bcd(bcd2));
    ip_bin2bcd #(.W(7))  u_bt (.clk(clk), .rst_n(rst_n), .bin(p2), .bcd(bcdt16));
    wire [15:0] bcdh;
    ip_bin2bcd #(.W(7))  u_bh (.clk(clk), .rst_n(rst_n), .bin(hours), .bcd(bcdh));

    // ------------------------------------------------------------------
    // 5. text: which character sits in this 32x32 cell?   15 = blank
    //    row 0, cols 12..15  : gearbox hours left + H   (top right, next to the oil lamp)
    //    row 1, cols 10..12  : T and the tooth count
    //    row 2, cols  2.. 8  : rpm1 + RPM        (left)
    //    row 2, cols 10..16  : rpm2 + RPM        (right)
    // ------------------------------------------------------------------
    wire [4:0] cx = x[9:5];
    wire [3:0] cy = y[8:5];
    wire [2:0] gx = x[4:2];
    wire [2:0] gy = y[4:2];

    // leading zeros are blanked
    wire [3:0] a3 = bcd1[15:12], a2 = bcd1[11:8], a1 = bcd1[7:4], a0 = bcd1[3:0];
    wire [3:0] b3 = bcd2[15:12], b2 = bcd2[11:8], b1 = bcd2[7:4], b0 = bcd2[3:0];
    wire [3:0] A3 = (a3 == 0) ? 4'd15 : a3;
    wire [3:0] A2 = (a3 == 0 && a2 == 0) ? 4'd15 : a2;
    wire [3:0] A1 = (a3 == 0 && a2 == 0 && a1 == 0) ? 4'd15 : a1;
    wire [3:0] B3 = (b3 == 0) ? 4'd15 : b3;
    wire [3:0] B2 = (b3 == 0 && b2 == 0) ? 4'd15 : b2;
    wire [3:0] B1 = (b3 == 0 && b2 == 0 && b1 == 0) ? 4'd15 : b1;
    wire [3:0] c2 = bcdh[11:8], c1 = bcdh[7:4], c0 = bcdh[3:0];
    wire [3:0] C2 = (c2 == 0) ? 4'd15 : c2;
    wire [3:0] C1 = (c2 == 0 && c1 == 0) ? 4'd15 : c1;

    reg [4:0] ch;
    always @(*) begin
        ch = 4'd15;
        if (cy == 4'd3 && oil_low) begin             // GAME OVER banner (row 3 = y 96..127, above the smoke)
            case (cx)
                5'd5:  ch = 5'd16;          // G
                5'd6:  ch = 5'd17;          // A
                5'd7:  ch = 5'd12;          // M
                5'd8:  ch = 5'd18;          // E
                5'd10: ch = 5'd19;          // O
                5'd11: ch = 5'd20;          // V
                5'd12: ch = 5'd18;          // E
                5'd13: ch = 5'd10;          // R
                default: ;
            endcase
        end else if (cy == 4'd14) begin
            case (cx)
                5'd8: ch = C2;
                5'd9: ch = C1;
                5'd10: ch = c0;
                5'd11: ch = 4'd14;          // H
                default: ;
            endcase
        end else if (cy == 4'd1) begin
            case (cx)
                5'd10: ch = 4'd13;          // T
                5'd11: ch = bcdt[7:4];
                5'd12: ch = bcdt[3:0];
                default: ;
            endcase
        end else if (cy == 4'd2) begin
            case (cx)
                5'd2:  ch = A3;
                5'd3:  ch = A2;
                5'd4:  ch = A1;
                5'd5:  ch = a0;
                5'd6:  ch = 4'd10;          // R
                5'd7:  ch = 4'd11;          // P
                5'd8:  ch = 4'd12;          // M
                5'd10: ch = B3;
                5'd11: ch = B2;
                5'd12: ch = B1;
                5'd13: ch = b0;
                5'd14: ch = 4'd10;
                5'd15: ch = 4'd11;
                5'd16: ch = 4'd12;
                default: ;
            endcase
        end
    end

    wire [4:0] grow;
    ip_font u_font (.ch(ch), .row(gy), .bits(grow));

    // glyph pixel: columns gx 1..5, rows gy 0..6 of the 8x8 cell
    // pick bit (5 - gx) of the row: shift it up to bit 8 (gx outside 1..5 shifts in zeros)
    wire [8:0] pshift = {1'b0, grow, 3'b000} << gx;
    wire px_on = pshift[8];
    wire text_on = px_on;

    // highlight the parameter being edited
    wire hl     = (!sel && cy == 4'd2 && cx < 5'd9) || (sel && cy == 4'd1 && can_shift);
    wire locked = sel && cy == 4'd1 && !can_shift;
    wire oil_txt = (oil_warn || oil_low) && cy == 4'd14;     // hours counter turns red at 5 h or less
    wire go_row  = oil_low && cy == 4'd3;                    // GAME OVER text row
    wire go_box  = go_row && cx >= 5'd4 && cx <= 5'd14;      // black box behind the banner


    // ------------------------------------------------------------------
    // 6. the gears
    //    Gear 1 is fixed: 12 teeth, pitch radius G1R, centre (G1X, GY).
    //    Gear 2 has p2 teeth and the SAME tooth size, so its pitch radius is p2 * 11/4 px and its
    //    centre sits G1R + r2 to the right of gear 1: the teeth really mesh at every tooth count.
    //    Gear 1 turns by alpha (65536 = one turn); the speed grows with rpm1, but is scaled down so
    //    2000 rpm is still readable on a 60 Hz picture.
    //    Gear 2 needs no angle of its own: meshing means  N * alpha2 = -12 * alpha1, so its tooth
    //    phase is simply  N * theta + 12 * alpha1 (+ half a tooth when N is even).
    // ------------------------------------------------------------------
    localparam [10:0] G1X = 11'd150;
    localparam [10:0] GY  = 11'd288;
    localparam [10:0] G1R = 11'd33;

    reg [15:0] alpha;
    wire [11:0] inc = {p1, 5'b0} - {p1, 2'b0};            // p1 * 28 -> up to 0.034 turn per picture
    always @(posedge clk) begin
        if (!rst_n)      alpha <= 16'd0;
        else if (frame)  alpha <= alpha + {4'b0, inc};
    end
    wire [11:0] a12 = alpha[15:4];

    // pixel offsets, looking 9 clocks ahead to cover the CORDIC pipeline latency
    wire [10:0] xa  = {1'b0, x} + 11'd9;
    wire [10:0] r11 = {1'b0, p2, 3'b0} + {3'b0, p2, 1'b0} + {4'b0, p2};   // 11 * p2
    wire [10:0] r2  = {2'b0, r11[10:2]};                                  // pitch radius of gear 2
    wire [10:0] dy  = {1'b0, y} - GY;

    // gear 1
    wire [10:0] rk1;
    wire [11:0] th1;
    wire        far1;
    ip_polar u_pol1 (.clk(clk), .dx(xa - G1X), .dy(dy), .rk(rk1), .th(th1), .far(far1));

    wire [11:0] t1   = th1 - a12;
    wire [11:0] phi1 = {t1[8:0], 3'b0} + {t1[9:0], 2'b0};       // 12 * t1, mod 4096
    wire [11:0] ps1  = phi1 + 12'd819;                           // tooth = +-20 % of the pitch
    wire        tooth1 = ps1 < 12'd1638;

    wire [10:0] k1tip, k1root, k1hole;
    ip_kmul u_k1a (.t(9'd37), .k(k1tip));
    ip_kmul u_k1b (.t(9'd28), .k(k1root));
    ip_kmul u_k1c (.t(9'd10), .k(k1hole));
    wire in1 = !far1 && (rk1 > k1hole) && ((rk1 < k1root) || ((rk1 < k1tip) && tooth1));

    // gear 2
    wire [10:0] rk2;
    wire [11:0] th2;
    wire        far2;
    wire [10:0] g2x = G1X + G1R + r2;
    ip_polar u_pol2 (.clk(clk), .dx(xa - g2x), .dy(dy), .rk(rk2), .th(th2), .far(far2));

    wire [17:0] m2   = th2 * p2;
    wire [14:0] a12x = {a12, 3'b0} + {a12, 2'b0};                // 12 * alpha, mod 4096 below
    wire [11:0] phi2 = m2[11:0] + a12x[11:0] + {~p2[0], 11'b0};
    wire [11:0] ps2  = phi2 + 12'd819;
    wire        tooth2 = ps2 < 12'd1638;

    wire [8:0]  r2t = r2[8:0] + 9'd4;
    wire [8:0]  r2r = r2[8:0] - 9'd5;
    wire [8:0]  r2h = {2'b0, r2[8:2]};
    wire [10:0] k2tip, k2root, k2hole;
    ip_kmul u_k2a (.t(r2t), .k(k2tip));
    ip_kmul u_k2b (.t(r2r), .k(k2root));
    ip_kmul u_k2c (.t(r2h), .k(k2hole));
    wire in2 = !far2 && (rk2 > k2hole) && ((rk2 < k2root) || ((rk2 < k2tip) && tooth2));

    // ------------------------------------------------------------------
    // 6b. oil can lamp (top right) and the oil drops falling into the gear mesh
    // ------------------------------------------------------------------
    wire lamp_shape =
        (x >= 10'd584 && x < 10'd616 && y >= 10'd24 && y < 10'd44) ||   // body
        (x >= 10'd568 && x < 10'd584 && y >= 10'd20 && y < 10'd26) ||   // spout
        (x >= 10'd558 && x < 10'd570 && y >= 10'd14 && y < 10'd22) ||   // spout tip
        (x >= 10'd616 && x < 10'd626 && y >= 10'd28 && y < 10'd32) ||   // handle, top
        (x >= 10'd622 && x < 10'd626 && y >= 10'd28 && y < 10'd42) ||   // handle, side
        (x >= 10'd616 && x < 10'd626 && y >= 10'd38 && y < 10'd42) ||   // handle, bottom
        (x >= 10'd560 && x < 10'd566 && y >= 10'd28 && y < 10'd38);     // drip
    wire lamp_on = (oil_warn || oil_low) && (refill || oil_low || fcount[4]);   // blinks while waiting, solid when out/refilling

    // three drops, 86 pixels apart, falling 4 px per picture from y=98 into the mesh at x = 179..186
    wire [7:0] ph0 = {oil_t[5:0], 2'b00};
    wire [7:0] ph1 = ph0 + 8'd86;
    wire [7:0] ph2 = ph0 + 8'd171;
    wire [9:0] dy0 = {2'b00, ph0} + 10'd98;
    wire [9:0] dy1 = {2'b00, ph1} + 10'd98;
    wire [9:0] dy2 = {2'b00, ph2} + 10'd98;
    wire drop_x = (x >= 10'd179) && (x < 10'd187);
    wire drop0 = refill && drop_x && (ph0 <= 8'd170) && (y >= dy0) && (y < dy0 + 10'd16);
    wire drop1 = refill && drop_x && (ph1 <= 8'd170) && (y >= dy1) && (y < dy1 + 10'd16);
    wire drop2 = refill && drop_x && (ph2 <= 8'd170) && (y >= dy2) && (y < dy2 + 10'd16);

    // smoke: ten grey puffs (two columns of five) rise from the top of both gears at GAME OVER
    wire smoke_on = oil_low;
    wire sm1_any, sm1_young, sm2_any, sm2_young;
    ip_smoke u_sm1 (.x(x), .y(y), .xs(G1X), .ys(GY - G1R - 11'd8), .t(fcount[6:0]),
                    .any(sm1_any), .young(sm1_young));
    ip_smoke u_sm2 (.x(x), .y(y), .xs(g2x), .ys(GY - r2 - 11'd8),  .t(fcount[6:0] + 7'd13),
                    .any(sm2_any), .young(sm2_young));
    wire smoke_any   = sm1_any   || sm2_any;
    wire smoke_young = sm1_young || sm2_young;

    // ------------------------------------------------------------------
    // 7. colour: text white (yellow when selected, red when P2 is locked), background dark blue, black outside the picture
    // ------------------------------------------------------------------
    assign rgb = !active ? 6'b00_00_00 :
                 text_on ? ((locked || oil_txt || go_row) ? 6'b11_00_00 : hl ? 6'b11_11_00 : 6'b11_11_11) :
                 go_box  ? 6'b00_00_00 :
                 (lamp_shape && lamp_on) ? 6'b11_00_00 :
                 (drop0 || drop1 || drop2) ? 6'b11_11_01 :
                 (smoke_on && smoke_any) ? (smoke_young ? 6'b10_10_10 : 6'b01_01_01) :
                 in1     ? 6'b11_10_00 :
                 in2     ? 6'b01_11_11 :
                           6'b00_00_01;
endmodule

// ===== vga_shell.v =====
// The VGA shell, given. Two modules:
//   vga_sync       makes the 640x480 at 60 Hz timing from a 25 MHz clock and says which pixel is being drawn.
//   vga_level_bar  draws a vertical bar whose height is an 8 bit level, for the tracks that show a number.
// You do not edit this file.

module vga_sync (
    input  wire       clk,
    input  wire       rst_n,
    output wire       hsync,    // active low
    output wire       vsync,    // active low
    output wire       active,   // high inside the 640x480 picture
    output wire [9:0] x,        // pixel column, 0 to 639 when active
    output wire [9:0] y,        // pixel row, 0 to 479 when active
    output wire       frame     // one clock pulse per picture, at the start of the blanking
);
    reg [9:0] hc, vc;

    always @(posedge clk) begin
        if (!rst_n) begin
            hc <= 10'd0;
            vc <= 10'd0;
        end else if (hc == 10'd799) begin
            hc <= 10'd0;
            vc <= (vc == 10'd524) ? 10'd0 : vc + 10'd1;
        end else begin
            hc <= hc + 10'd1;
        end
    end

    assign x      = hc;
    assign y      = vc;
    assign active = (hc < 10'd640) && (vc < 10'd480);
    assign hsync  = ~((hc >= 10'd656) && (hc < 10'd752));
    assign vsync  = ~((vc >= 10'd490) && (vc < 10'd492));
    assign frame  = (hc == 10'd640) && (vc == 10'd480);
endmodule


// ===== ip_debounce.v =====
// Synchronises a noisy input and only changes the output when the input has held steady for N clocks.

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

// ===== ip_tick.v =====
// A tick generator: one pulse every DIV enabled clock cycles.

module ip_tick #(
    parameter DIV = 4
) (
    input  wire clk,
    input  wire rst_n,
    input  wire en,
    output wire tick
);
    reg [19:0] count;

    assign tick = en && (count == DIV - 1);

    always @(posedge clk) begin
        if (!rst_n) begin
            count <= 20'd0;
        end else if (en) begin
            if (count == DIV - 1) count <= 20'd0;
            else                  count <= count + 20'd1;
        end
    end
endmodule

// ===== ip_div.v =====
// Serial restoring divider: quo = num / den, truncated. Runs forever; a new result appears
// every NW+1 clocks. Inputs are latched at the start of each run so the result never glitches.

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

// ===== ip_bin2bcd.v =====
// Serial double-dabble: turns an unsigned W bit number into 4 BCD digits (digit 0 = lowest nibble).
// Runs forever; a fresh result is latched every W+1 clocks.
// Written without generate / indexed part-selects so simple Verilog parsers accept it.

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
            hi  <= {d3[2:0], d2, d1, d0, lo[W-1]};     // shift the whole 16 bits left by one
            lo  <= {lo[W-2:0], 1'b0};
            cnt <= cnt + 5'd1;
        end
    end
endmodule

// ===== ip_font.v =====
// 5x7 font for the characters the display needs.
// ch (5 bits): 0-9 digits, 10 R, 11 P, 12 M, 13 T, 14 H, 16 G, 17 A, 18 E, 19 O, 20 V; anything else blank (15 = space).
// row: 0 (top) .. 6, anything else blank. bits: the 5 pixels of that row, leftmost pixel is the MSB.
// One flat case on {ch,row} with 5 bit results (no wide constants, no nested lookups).

module ip_font (
    input  wire [4:0]  ch,
    input  wire [2:0]  row,
    output reg  [4:0]  bits
);
    always @(*) begin
        case ({ch, row})
            8'd0: bits = 5'b01110;
            8'd1: bits = 5'b10001;
            8'd2: bits = 5'b10011;
            8'd3: bits = 5'b10101;
            8'd4: bits = 5'b11001;
            8'd5: bits = 5'b10001;
            8'd6: bits = 5'b01110;
            8'd8: bits = 5'b00100;
            8'd9: bits = 5'b01100;
            8'd10: bits = 5'b00100;
            8'd11: bits = 5'b00100;
            8'd12: bits = 5'b00100;
            8'd13: bits = 5'b00100;
            8'd14: bits = 5'b01110;
            8'd16: bits = 5'b01110;
            8'd17: bits = 5'b10001;
            8'd18: bits = 5'b00001;
            8'd19: bits = 5'b00010;
            8'd20: bits = 5'b00100;
            8'd21: bits = 5'b01000;
            8'd22: bits = 5'b11111;
            8'd24: bits = 5'b11110;
            8'd25: bits = 5'b00001;
            8'd26: bits = 5'b00001;
            8'd27: bits = 5'b01110;
            8'd28: bits = 5'b00001;
            8'd29: bits = 5'b00001;
            8'd30: bits = 5'b11110;
            8'd32: bits = 5'b00010;
            8'd33: bits = 5'b00110;
            8'd34: bits = 5'b01010;
            8'd35: bits = 5'b10010;
            8'd36: bits = 5'b11111;
            8'd37: bits = 5'b00010;
            8'd38: bits = 5'b00010;
            8'd40: bits = 5'b11111;
            8'd41: bits = 5'b10000;
            8'd42: bits = 5'b11110;
            8'd43: bits = 5'b00001;
            8'd44: bits = 5'b00001;
            8'd45: bits = 5'b10001;
            8'd46: bits = 5'b01110;
            8'd48: bits = 5'b00110;
            8'd49: bits = 5'b01000;
            8'd50: bits = 5'b10000;
            8'd51: bits = 5'b11110;
            8'd52: bits = 5'b10001;
            8'd53: bits = 5'b10001;
            8'd54: bits = 5'b01110;
            8'd56: bits = 5'b11111;
            8'd57: bits = 5'b00001;
            8'd58: bits = 5'b00010;
            8'd59: bits = 5'b00100;
            8'd60: bits = 5'b01000;
            8'd61: bits = 5'b01000;
            8'd62: bits = 5'b01000;
            8'd64: bits = 5'b01110;
            8'd65: bits = 5'b10001;
            8'd66: bits = 5'b10001;
            8'd67: bits = 5'b01110;
            8'd68: bits = 5'b10001;
            8'd69: bits = 5'b10001;
            8'd70: bits = 5'b01110;
            8'd72: bits = 5'b01110;
            8'd73: bits = 5'b10001;
            8'd74: bits = 5'b10001;
            8'd75: bits = 5'b01111;
            8'd76: bits = 5'b00001;
            8'd77: bits = 5'b00010;
            8'd78: bits = 5'b01100;
            8'd80: bits = 5'b11110; // R
            8'd81: bits = 5'b10001;
            8'd82: bits = 5'b10001;
            8'd83: bits = 5'b11110;
            8'd84: bits = 5'b10100;
            8'd85: bits = 5'b10010;
            8'd86: bits = 5'b10001;
            8'd88: bits = 5'b11110; // P
            8'd89: bits = 5'b10001;
            8'd90: bits = 5'b10001;
            8'd91: bits = 5'b11110;
            8'd92: bits = 5'b10000;
            8'd93: bits = 5'b10000;
            8'd94: bits = 5'b10000;
            8'd96: bits = 5'b10001; // M
            8'd97: bits = 5'b11011;
            8'd98: bits = 5'b10101;
            8'd99: bits = 5'b10101;
            8'd100: bits = 5'b10001;
            8'd101: bits = 5'b10001;
            8'd102: bits = 5'b10001;
            8'd104: bits = 5'b11111; // T
            8'd105: bits = 5'b00100;
            8'd106: bits = 5'b00100;
            8'd107: bits = 5'b00100;
            8'd108: bits = 5'b00100;
            8'd109: bits = 5'b00100;
            8'd110: bits = 5'b00100;
            8'd112: bits = 5'b10001; // H
            8'd113: bits = 5'b10001;
            8'd114: bits = 5'b10001;
            8'd115: bits = 5'b11111;
            8'd116: bits = 5'b10001;
            8'd117: bits = 5'b10001;
            8'd118: bits = 5'b10001;
            8'd128: bits = 5'b01110; // G
            8'd129: bits = 5'b10001;
            8'd130: bits = 5'b10000;
            8'd131: bits = 5'b10111;
            8'd132: bits = 5'b10001;
            8'd133: bits = 5'b10001;
            8'd134: bits = 5'b01111;
            8'd136: bits = 5'b01110; // A
            8'd137: bits = 5'b10001;
            8'd138: bits = 5'b10001;
            8'd139: bits = 5'b11111;
            8'd140: bits = 5'b10001;
            8'd141: bits = 5'b10001;
            8'd142: bits = 5'b10001;
            8'd144: bits = 5'b11111; // E
            8'd145: bits = 5'b10000;
            8'd146: bits = 5'b10000;
            8'd147: bits = 5'b11110;
            8'd148: bits = 5'b10000;
            8'd149: bits = 5'b10000;
            8'd150: bits = 5'b11111;
            8'd152: bits = 5'b01110; // O
            8'd153: bits = 5'b10001;
            8'd154: bits = 5'b10001;
            8'd155: bits = 5'b10001;
            8'd156: bits = 5'b10001;
            8'd157: bits = 5'b10001;
            8'd158: bits = 5'b01110;
            8'd160: bits = 5'b10001; // V
            8'd161: bits = 5'b10001;
            8'd162: bits = 5'b10001;
            8'd163: bits = 5'b10001;
            8'd164: bits = 5'b10001;
            8'd165: bits = 5'b01010;
            8'd166: bits = 5'b00100;
            default: bits = 5'b00000;
        endcase
    end
endmodule

// ===== ip_polar.v =====
// Cartesian -> polar for the gear drawing, a pipelined CORDIC (vectoring mode, 8 iterations).
//
//   in : dx, dy  = pixel offset from the gear centre, 11 bit two's complement
//   out: rk      = radius * 1.6468   (the CORDIC gain; compare against thresholds scaled the same way)
//        th      = angle, 12 bit, 4096 = one full turn (screen coordinates, y down)
//        far     = offset too big (|dx| or |dy| >= 256), rk / th are meaningless
//
// Latency is LAT = 9 clocks (one input register + 8 iterations). The caller feeds the pixel
// that will be on screen LAT clocks later, i.e. x + 9, so the result lines up with the beam.

module ip_cordic_stage #(
    parameter I = 0,
    parameter [11:0] A = 12'd0       // atan(2^-I) in 1/4096 turns
) (
    input  wire        clk,
    input  wire [10:0] xi,           // unsigned
    input  wire [10:0] yi,           // two's complement
    input  wire [11:0] zi,
    output reg  [10:0] xo,
    output reg  [10:0] yo,
    output reg  [11:0] zo
);
    // arithmetic shift right of yi by I, spelled out with plain logic shifts (no >>> / $signed)
    wire [10:0] yfill = yi[10] ? ~(11'h7FF >> I) : 11'd0;
    wire [10:0] ysh   = (yi >> I) | yfill;
    wire [10:0] xsh = xi >> I;

    always @(posedge clk) begin
        if (!yi[10]) begin
            xo <= xi + ysh;
            yo <= yi - xsh;
            zo <= zi + A;
        end else begin
            xo <= xi - ysh;
            yo <= yi + xsh;
            zo <= zi - A;
        end
    end
endmodule

module ip_polar (
    input  wire        clk,
    input  wire [10:0] dx,
    input  wire [10:0] dy,
    output wire [10:0] rk,
    output reg  [11:0] th,
    output wire        far
);
    // |dx|, |dy| and the quadrant
    wire [10:0] ax = dx[10] ? (11'd0 - dx) : dx;
    wire [10:0] ay = dy[10] ? (11'd0 - dy) : dy;
    wire        far_c = (ax[10:8] != 3'd0) || (ay[10:8] != 3'd0);

    reg [10:0] x0, y0;
    reg [8:0]  sxp, syp, farp;      // quadrant and far flag travel down the pipeline

    always @(posedge clk) begin
        x0   <= {2'b00, ax[8:0]};
        y0   <= {2'b00, ay[8:0]};
        sxp  <= {sxp[7:0], dx[10]};
        syp  <= {syp[7:0], dy[10]};
        farp <= {farp[7:0], far_c};
    end

    wire [10:0] x1, y1, x2, y2, x3, y3, x4, y4, x5, y5, x6, y6, x7, y7, x8, y8;
    wire [11:0] z1, z2, z3, z4, z5, z6, z7, z8;

    ip_cordic_stage #(.I(0), .A(12'd512)) s0 (.clk(clk), .xi(x0), .yi(y0), .zi(12'd0), .xo(x1), .yo(y1), .zo(z1));
    ip_cordic_stage #(.I(1), .A(12'd302)) s1 (.clk(clk), .xi(x1), .yi(y1), .zi(z1),    .xo(x2), .yo(y2), .zo(z2));
    ip_cordic_stage #(.I(2), .A(12'd160)) s2 (.clk(clk), .xi(x2), .yi(y2), .zi(z2),    .xo(x3), .yo(y3), .zo(z3));
    ip_cordic_stage #(.I(3), .A(12'd81))  s3 (.clk(clk), .xi(x3), .yi(y3), .zi(z3),    .xo(x4), .yo(y4), .zo(z4));
    ip_cordic_stage #(.I(4), .A(12'd41))  s4 (.clk(clk), .xi(x4), .yi(y4), .zi(z4),    .xo(x5), .yo(y5), .zo(z5));
    ip_cordic_stage #(.I(5), .A(12'd20))  s5 (.clk(clk), .xi(x5), .yi(y5), .zi(z5),    .xo(x6), .yo(y6), .zo(z6));
    ip_cordic_stage #(.I(6), .A(12'd10))  s6 (.clk(clk), .xi(x6), .yi(y6), .zi(z6),    .xo(x7), .yo(y7), .zo(z7));
    ip_cordic_stage #(.I(7), .A(12'd5))   s7 (.clk(clk), .xi(x7), .yi(y7), .zi(z7),    .xo(x8), .yo(y8), .zo(z8));

    assign rk  = x8;
    assign far = farp[8];

    // fold the first-quadrant angle back into the right quadrant
    always @(*) begin
        if (!sxp[8] && !syp[8])      th = z8;
        else if (sxp[8] && !syp[8])  th = 12'd2048 - z8;
        else if (sxp[8] && syp[8])   th = 12'd2048 + z8;
        else                         th = 12'd0 - z8;
    end

    wire _unused = &{y8, 1'b0};
endmodule

// radius threshold * 1.6468 (the CORDIC gain), as shift-add: t * (1 + 1/2 + 1/8 + 1/64 + 1/128)
module ip_kmul (
    input  wire [8:0]  t,
    output wire [10:0] k
);
    assign k = {2'b0, t} + {3'b0, t[8:1]} + {5'b0, t[8:3]} + {8'b0, t[8:6]} + {9'b0, t[8:7]};
endmodule

// ===== ip_puff.v =====
// One round-ish smoke puff: an octagon of half-size hs centred on (xc, yc).
// Inside when |dx| < hs, |dy| < hs and |dx| + |dy| < 1.5 * hs (the square with its corners cut off).

module ip_puff (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [10:0] xc,
    input  wire [10:0] yc,
    input  wire [3:0]  hs,
    output wire        hit
);
    wire [10:0] xe  = {1'b0, x};
    wire [10:0] ye  = {1'b0, y};
    wire [10:0] dxa = (xe >= xc) ? (xe - xc) : (xc - xe);
    wire [10:0] dya = (ye >= yc) ? (ye - yc) : (yc - ye);
    wire [10:0] h   = {7'b0, hs};
    assign hit = (dxa < h) && (dya < h) && ((dxa + dya) < (h + {1'b0, h[10:1]}));
endmodule

// ===== ip_smoke.v =====
// A column of smoke above a source point (xs, ys): five puffs, each living 128 pictures.
// A puff rises about 0.75 px per picture (up to ~94 px), wobbles sideways, grows (half-size 4..11) and darkens with age.
// t is the picture counter (the caller adds a phase so two columns do not move in step).

module ip_smoke (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [10:0] xs,
    input  wire [10:0] ys,
    input  wire [6:0]  t,
    output wire        any,
    output wire        young       // the puff that was hit is in the first half of its life
);
    wire [6:0] a0 = t;
    wire [6:0] a1 = t + 7'd26;
    wire [6:0] a2 = t + 7'd51;
    wire [6:0] a3 = t + 7'd77;
    wire [6:0] a4 = t + 7'd102;

    wire [3:0] w0 = a0[4] ? ~a0[3:0] : a0[3:0];          // triangle wave 0..15 = the wobble
    wire [3:0] w1 = a1[4] ? ~a1[3:0] : a1[3:0];
    wire [3:0] w2 = a2[4] ? ~a2[3:0] : a2[3:0];
    wire [3:0] w3 = a3[4] ? ~a3[3:0] : a3[3:0];
    wire [3:0] w4 = a4[4] ? ~a4[3:0] : a4[3:0];

    wire [10:0] x0 = xs - 11'd14 + {7'b0, w0};
    wire [10:0] x1 = xs -  11'd2 + {7'b0, w1};
    wire [10:0] x2 = xs - 11'd10 + {7'b0, w2};
    wire [10:0] x3 = xs +  11'd2 + {7'b0, w3};
    wire [10:0] x4 = xs -  11'd6 + {7'b0, w4};
    wire [10:0] y0 = ys - {5'b0, a0[6:1]} - {6'b0, a0[6:2]};
    wire [10:0] y1 = ys - {5'b0, a1[6:1]} - {6'b0, a1[6:2]};
    wire [10:0] y2 = ys - {5'b0, a2[6:1]} - {6'b0, a2[6:2]};
    wire [10:0] y3 = ys - {5'b0, a3[6:1]} - {6'b0, a3[6:2]};
    wire [10:0] y4 = ys - {5'b0, a4[6:1]} - {6'b0, a4[6:2]};

    wire p0, p1, p2, p3, p4;
    ip_puff u0 (.x(x), .y(y), .xc(x0), .yc(y0), .hs({1'b0, a0[6:4]} + 4'd4), .hit(p0));
    ip_puff u1 (.x(x), .y(y), .xc(x1), .yc(y1), .hs({1'b0, a1[6:4]} + 4'd4), .hit(p1));
    ip_puff u2 (.x(x), .y(y), .xc(x2), .yc(y2), .hs({1'b0, a2[6:4]} + 4'd4), .hit(p2));
    ip_puff u3 (.x(x), .y(y), .xc(x3), .yc(y3), .hs({1'b0, a3[6:4]} + 4'd4), .hit(p3));
    ip_puff u4 (.x(x), .y(y), .xc(x4), .yc(y4), .hs({1'b0, a4[6:4]} + 4'd4), .hit(p4));

    assign any   = p0 || p1 || p2 || p3 || p4;
    assign young = (p0 && !a0[6]) || (p1 && !a1[6]) || (p2 && !a2[6]) || (p3 && !a3[6]) || (p4 && !a4[6]);
endmodule

// ===== pwm.v =====
// PWM output: high while the free-running counter is below duty.
// The counter advances once every PRE clocks, so the PWM frequency is clk / (PRE * 256).
// 25 MHz / (8 * 256) = ~12 kHz.

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

