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
`default_nettype none

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
    //    Gear 2 has p2 teeth and the SAME tooth size, so its pitch radius is p2 * 15/8 px and its
    //    centre sits G1R + r2 to the right of gear 1: the teeth really mesh at every tooth count.
    //    Gear 1 turns by alpha (65536 = one turn); the speed grows with rpm1, but is scaled down so
    //    2000 rpm is still readable on a 60 Hz picture.
    //    Gear 2 needs no angle of its own: meshing means  N * alpha2 = -12 * alpha1, so its tooth
    //    phase is simply  N * theta + 12 * alpha1 (+ half a tooth when N is even).
    //    Radii: 12 teeth -> 22 px, 64 teeth -> 120 px, so offsets stay below 64 (gear 1) / 128 (gear 2)
    //    and the polar converters can use small datapaths.
    // ------------------------------------------------------------------
    localparam [10:0] G1X = 11'd150;
    localparam [10:0] GY  = 11'd288;
    localparam [10:0] G1R = 11'd22;

    reg [15:0] alpha;
    wire [11:0] inc = {p1, 5'b0} - {p1, 2'b0};            // p1 * 28 -> up to 0.034 turn per picture
    always @(posedge clk) begin
        if (!rst_n)      alpha <= 16'd0;
        else if (frame)  alpha <= alpha + {4'b0, inc};
    end
    wire [11:0] a12 = alpha[15:4];

    // pixel offsets, looking 9 clocks ahead to cover the CORDIC pipeline latency
    wire [10:0] xa  = {1'b0, x} + 11'd9;
    wire [10:0] r15 = {p2, 4'b0} - {4'b0, p2};            // 15 * p2
    wire [10:0] r2  = {3'b0, r15[10:3]};                  // pitch radius of gear 2 = 15 * p2 / 8
    wire [10:0] dy  = {1'b0, y} - GY;

    // gear 1
    wire [7:0]  rk1;
    wire [11:0] th1;
    wire        far1;
    ip_polar #(.M(6)) u_pol1 (.clk(clk), .dx(xa - G1X), .dy(dy), .rk(rk1), .th(th1), .far(far1));

    wire [11:0] t1   = th1 - a12;
    wire [11:0] phi1 = {t1[8:0], 3'b0} + {t1[9:0], 2'b0};       // 12 * t1, mod 4096
    wire [11:0] ps1  = phi1 + 12'd819;                           // tooth = +-20 % of the pitch
    wire        tooth1 = ps1 < 12'd1638;

    // radius thresholds, scaled by the CORDIC gain 1.6468: tip = r + 3, root = r - 5, hub hole = 6
    wire [10:0] k1tip, k1root, k1hole;
    ip_kmul u_k1a (.t(9'd25), .k(k1tip));
    ip_kmul u_k1b (.t(9'd17), .k(k1root));
    ip_kmul u_k1c (.t(9'd6),  .k(k1hole));
    wire in1 = !far1 && ({3'b0, rk1} > k1hole) && (({3'b0, rk1} < k1root) || (({3'b0, rk1} < k1tip) && tooth1));

    // gear 2
    wire [8:0]  rk2;
    wire [11:0] th2;
    wire        far2;
    wire [10:0] g2x = G1X + G1R + r2;
    ip_polar #(.M(7)) u_pol2 (.clk(clk), .dx(xa - g2x), .dy(dy), .rk(rk2), .th(th2), .far(far2));

    wire [17:0] m2   = th2 * p2;
    wire [14:0] a12x = {a12, 3'b0} + {a12, 2'b0};                // 12 * alpha, mod 4096 below
    wire [11:0] phi2 = m2[11:0] + a12x[11:0] + {~p2[0], 11'b0};
    wire [11:0] ps2  = phi2 + 12'd819;
    wire        tooth2 = ps2 < 12'd1638;

    // one gain multiply for gear 2, the other thresholds are fixed offsets from it (K*3 = 5, K*5 = 8)
    wire [10:0] kr2;
    ip_kmul u_k2 (.t(r2[8:0]), .k(kr2));
    wire [10:0] k2tip  = kr2 + 11'd5;
    wire [10:0] k2root = kr2 - 11'd8;
    wire [10:0] k2hole = {2'b0, kr2[10:2]};                      // hub hole = r / 4
    wire in2 = !far2 && ({2'b0, rk2} > k2hole) && (({2'b0, rk2} < k2root) || (({2'b0, rk2} < k2tip) && tooth2));

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

    // smoke: a noisy plume rises from the top of each gear at GAME OVER
    wire smoke_on = oil_low;
    wire sm1_any, sm1_young, sm2_any, sm2_young;
    ip_plume u_sm1 (.x(x), .y(y), .xs(G1X), .ys(GY - G1R - 11'd6), .t(fcount),
                    .on(sm1_any), .young(sm1_young));
    ip_plume u_sm2 (.x(x), .y(y), .xs(g2x), .ys(GY - r2  - 11'd6), .t(fcount + 8'd37),
                    .on(sm2_any), .young(sm2_young));
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
