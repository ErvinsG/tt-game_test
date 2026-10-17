// Gear ratio demo, small version (aims at one tile): bars instead of digits, one shared gear datapath.
//
//   P1 = motor speed, index 0..80 -> 0..2000 rpm in steps of 25      (top bar)
//   P2 = teeth of gear 2, 12..64                                       (second bar)
//   hours = gearbox working hours left                                 (third bar)
//
// Buttons: left selects P1, right selects P2, up/down change the selected one.
// Select = clutch: the tooth count (P2) can only be changed while the clutch is held or the motor is at 0 rpm.
// Oil: the hours run down while the motor turns. At 5 h or less the hours bar blinks red and the clutch adds oil
// (bar turns green, hours back to full). At 0 h it is GAME OVER: red background and bar, motor forced to 0 rpm,
// controls locked; only reset restarts.
//
// Screen: three bars at x = 32.., rows y = 32 / 64 / 96 (16 px high, 4 px per unit); the two meshing octagon
// gears (ip_octgear.v) below them.
`default_nettype none

module game_core #(
    parameter STEP    = 4,       // change a value every STEP pictures while up/down is held
    parameter HSTART  = 12       // hours at reset (100 for the full game, a small value to see the warning quickly)
                                 // one hour = 32 pictures (0.53 s) of running, so 100 h last about 53 s
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
    // 1. buttons: sampled once per picture
    // ------------------------------------------------------------------
    wire left_c, right_c, up_c, down_c, clutch_c;
    ip_btn db_left  (.clk(clk), .rst_n(rst_n), .tick(frame), .raw(left),   .clean(left_c));
    ip_btn db_right (.clk(clk), .rst_n(rst_n), .tick(frame), .raw(right),  .clean(right_c));
    ip_btn db_up    (.clk(clk), .rst_n(rst_n), .tick(frame), .raw(up),     .clean(up_c));
    ip_btn db_down  (.clk(clk), .rst_n(rst_n), .tick(frame), .raw(down),   .clean(down_c));
    ip_btn db_clutch(.clk(clk), .rst_n(rst_n), .tick(frame), .raw(clutch), .clean(clutch_c));

    reg [6:0] hours;          // gearbox working hours left
    wire      oil_low  = (hours == 7'd0);                  // GAME OVER
    wire      oil_warn = (hours <= 7'd5) && !oil_low;      // 5 h or less: the clutch can add oil

    // one pulse every STEP pictures
    reg [2:0] stepc;
    wire step = frame && (stepc == STEP - 1);
    always @(posedge clk) begin
        if (!rst_n)      stepc <= 3'd0;
        else if (frame)  stepc <= step ? 3'd0 : stepc + 3'd1;
    end

    // ------------------------------------------------------------------
    // 2. parameters
    // ------------------------------------------------------------------
    reg       sel;            // 0 = editing P1, 1 = editing P2
    reg [6:0] p1;             // rpm / 25, 0..80
    reg [6:0] p2;             // teeth, 12..64

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

    // ------------------------------------------------------------------
    // 3. PWM: 64 levels, duty = rpm / 2000 * 64 ~ p1 * 0.78. The VGA pixel counter doubles as the PWM counter
    //    (period 256 clocks = 98 kHz).
    // ------------------------------------------------------------------
    wire [5:0] duty = p1[6:1] + p1[6:2] + {4'b0, p1[6:5]};    // p1 * 0.78125 (80 -> 62 of 64)
    reg pwm_q;
    always @(posedge clk) pwm_q <= (x[7:2] < duty);
    assign pwm_out = pwm_q;

    // ------------------------------------------------------------------
    // 4. gearbox oil. fc is a free running picture counter: bit 4 blinks the oil square, an hour passes
    //    every time fc[4:0] wraps while the motor turns, and a refill lasts until fc[5:0] wraps after fc[6]
    //    has flipped (64..128 pictures).
    // ------------------------------------------------------------------
    reg [6:0] fc;
    reg       refill;         // oil is being added
    reg       rb;             // fc[6] when the refill started
    reg       clutch_d;
    wire      running = (p1 != 7'd0);
    wire      hour_tick = frame && running && !refill && !oil_low && (fc[4:0] == 5'd31);
    wire      clutch_rise = clutch_c && !clutch_d;
    wire      refill_end  = frame && refill && (fc[5:0] == 6'd63) && (fc[6] != rb);

    always @(posedge clk) begin
        clutch_d <= clutch_c;
        if (!rst_n) begin
            hours  <= HSTART;
            refill <= 1'b0;
            rb     <= 1'b0;
            fc     <= 7'd0;
        end else begin
            if (frame) fc <= fc + 7'd1;
            if (hour_tick) hours <= hours - 7'd1;

            if (clutch_rise && oil_warn && !refill) begin
                refill <= 1'b1;
                rb     <= fc[6];
            end else if (refill_end) begin
                refill <= 1'b0;
                hours  <= 7'd100;
            end
        end
    end

    // ------------------------------------------------------------------
    // 5. the gears: ONE octagon datapath for both. Left of the contact plane (x < 179) it draws gear 1
    //    (12 teeth, inradius 29, centre x = 150), right of it gear 2 (p2 teeth, inradius ~2.41 * p2, centre
    //    at 179 + r2). Gear 2 turns the other way and is half a tooth off so the teeth interleave.
    //    rot_acc is the rotation in px (6 fraction bits), up to 5 px (0.31 tooth) per picture.
    // ------------------------------------------------------------------
    reg [9:0] rot_acc;
    always @(posedge clk) begin
        if (!rst_n)      rot_acc <= 10'd0;
        else if (frame)  rot_acc <= rot_acc + {1'b0, p1, 2'b00};    // p1 / 16 px per picture
    end
    wire [3:0] rot1 = rot_acc[9:6];
    wire [3:0] n9   = p2[3:0] + {p2[0], 3'b000};          // 9 * N mod 16
    wire [3:0] rot2 = 4'd8 - n9 - rot1;

    wire [8:0] pn  = {2'b00, p2};
    wire [8:0] r2  = (pn << 1) + (pn >> 2) + (pn >> 3) + (pn >> 5);   // inradius of gear 2

    // coordinates relative to the contact plane u = x - 179: gear 1 is centred at u = -29, gear 2 at u = +r2
    wire [10:0] u     = {1'b0, x} - 11'd179;
    wire        sel2  = !u[10];                                  // x >= 179
    wire [10:0] csel  = sel2 ? {2'b00, r2} : 11'h7E3;            // 11'h7E3 = -29
    wire [8:0]  rsel  = sel2 ? r2 : 9'd29;
    wire [3:0]  nsel  = sel2 ? p2[3:0] : 4'd12;
    wire [3:0]  rotsel = sel2 ? rot2 : rot1;

    wire hit;
    ip_octgear u_gear (.dx(u - csel), .dy({1'b0, y} - 11'd288),
                       .root(rsel - 9'd4), .tip(rsel + 9'd2), .n4(nsel), .rot(rotsel), .hit(hit));

    // ------------------------------------------------------------------
    // 6. bars: one shared comparison for the three bars (4 px per unit, starting at x = 32)
    // ------------------------------------------------------------------
    wire [5:0] row  = y[9:4];                              // 16 px rows
    wire       r_p1 = (row == 6'd2);
    wire       r_p2 = (row == 6'd4);
    wire       r_hr = (row == 6'd6);
    wire       in_bar = (r_p1 || r_p2 || r_hr) && (x[9:2] >= 8'd8);
    wire [7:0] xo   = x[9:2] - 8'd8;
    wire [6:0] val  = r_p1 ? p1 : r_p2 ? p2 : hours;
    wire       track = in_bar && (xo < 8'd101);                // all three tracks are 100 units long
    wire       fill  = track && (xo < {1'b0, val});

    // fill colours: yellow = being edited, red = locked / low oil, white otherwise
    wire [5:0] fcol = r_p1 ? (!sel ? 6'b11_11_00 : 6'b11_11_11) :
                      r_p2 ? (sel ? (can_shift ? 6'b11_11_00 : 6'b11_00_00) : 6'b11_11_11) :
                             refill ? 6'b00_11_00 :                                  // green while the oil goes in
                             oil_low ? 6'b11_00_00 :                                 // game over: solid red
                             oil_warn ? (fc[4] ? 6'b11_00_00 : 6'b11_11_11) :        // low: blinks red / white
                             6'b00_11_11;

    // ------------------------------------------------------------------
    // 7. colour (registered: the long gear logic gets a full clock, the picture moves one pixel)
    // ------------------------------------------------------------------
    wire [5:0] rgb_d = !active ? 6'b00_00_00 :
                       fill    ? fcol :
                       track   ? 6'b01_01_01 :
                       (hit && !sel2) ? 6'b11_10_00 :
                       (hit &&  sel2) ? 6'b01_11_11 :
                       oil_low ? 6'b01_00_00 :
                                 6'b00_00_01;
    reg [5:0] rgb_q;
    always @(posedge clk) rgb_q <= rgb_d;
    assign rgb = rgb_q;
endmodule
