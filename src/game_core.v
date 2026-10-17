// Gear ratio demo: parameters, rpm2, PWM, text and two meshing gears on screen.
//
//   P1 = motor speed, index 0..80 -> 0..2000 rpm in steps of 25
//   P2 = teeth of gear 2, 12..64
//   rpm2 = rpm1 * 12 / P2
//
// Buttons: left selects P1, right selects P2, up/down change the selected one.
// Select = clutch: the tooth count (P2) can only be changed while the clutch is held or the motor is at 0 rpm.
// Screen: 20 x 15 text cells of 32 x 32 pixels (a 5x7 glyph drawn at 4x scale).
`default_nettype none

module game_core #(
    parameter DB   = 500000,     // debounce time in clocks, 20 ms at 25 MHz
    parameter STEP = 4           // change a value every STEP pictures while up/down is held
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

    wire step;
    ip_tick #(.DIV(STEP)) step_tick (.clk(clk), .rst_n(rst_n), .en(frame), .tick(step));

    // ------------------------------------------------------------------
    // 2. parameters
    // ------------------------------------------------------------------
    reg       sel;            // 0 = editing P1, 1 = editing P2
    reg [6:0] p1;             // rpm / 25, 0..80
    reg [5:0] p2;             // teeth, 12..64

    // the gears can only be swapped when they are not driven (0 rpm) or the clutch is pressed
    wire can_shift = clutch_c || (p1 == 7'd0);

    // a press acts at once (rising edge); holding the button repeats every STEP pictures
    reg up_d, down_d;
    always @(posedge clk) begin
        up_d   <= up_c;
        down_d <= down_c;
    end
    wire up_rise   = up_c   && !up_d;
    wire down_rise = down_c && !down_d;

    always @(posedge clk) begin
        if (!rst_n) begin
            sel <= 1'b0;
            p1  <= 7'd40;     // 1000 rpm
            p2  <= 6'd12;
        end else begin
            if (left_c && !right_c)      sel <= 1'b0;
            else if (right_c && !left_c) sel <= 1'b1;

            if (step || up_rise || down_rise) begin
                if (!sel) begin
                    if (up_c && !down_c)      p1 <= (p1 < 7'd80) ? p1 + 7'd1 : p1;
                    else if (down_c && !up_c) p1 <= (p1 > 7'd0)  ? p1 - 7'd1 : p1;
                end else if (can_shift) begin
                    if (up_c && !down_c)      p2 <= (p2 < 6'd64) ? p2 + 6'd1 : p2;
                    else if (down_c && !up_c) p2 <= (p2 > 6'd12) ? p2 - 6'd1 : p2;
                end
            end
        end
    end

    // rpm1 = p1 * 25
    wire [10:0] rpm1 = {p1, 4'b0} + {p1, 3'b0} + p1;

    // rpm2 = rpm1 * 12 / p2 = p1 * 300 / p2
    wire [14:0] num2 = {p1, 8'b0} + {p1, 5'b0} + {p1, 3'b0} + {p1, 2'b0};
    wire [14:0] rpm2_w;
    ip_div #(.NW(15), .DW(6)) u_div (.clk(clk), .rst_n(rst_n), .num(num2), .den(p2), .quo(rpm2_w));
    wire [10:0] rpm2 = rpm2_w[10:0];

    // ------------------------------------------------------------------
    // 3. PWM: duty = rpm1 / 2000 * 255 = p1 * 3.1875 (p1 = 80 -> 255)
    // ------------------------------------------------------------------
    wire [7:0] duty = {p1, 1'b0} + p1 + {3'b0, p1[6:3]} + {4'b0, p1[6:4]};
    pwm #(.PRE(8)) u_pwm (.clk(clk), .rst_n(rst_n), .duty(duty), .pwm_out(pwm_out));

    // ------------------------------------------------------------------
    // 4. binary -> decimal digits
    // ------------------------------------------------------------------
    wire [15:0] bcd1, bcd2;
    wire [15:0] bcdt16;
    wire [7:0]  bcdt = bcdt16[7:0];
    ip_bin2bcd #(.W(11)) u_b1 (.clk(clk), .rst_n(rst_n), .bin(rpm1), .bcd(bcd1));
    ip_bin2bcd #(.W(11)) u_b2 (.clk(clk), .rst_n(rst_n), .bin(rpm2), .bcd(bcd2));
    ip_bin2bcd #(.W(6))  u_bt (.clk(clk), .rst_n(rst_n), .bin(p2), .bcd(bcdt16));

    // ------------------------------------------------------------------
    // 5. text: which character sits in this 32x32 cell?   15 = blank
    //    row 1, cols  9..11  : T and the tooth count
    //    row 2, cols  2.. 8  : rpm1 + RPM        (left)
    //    row 2, cols  9..15  : rpm2 + RPM        (right)
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

    reg [3:0] ch;
    always @(*) begin
        ch = 4'd15;
        if (cy == 4'd1) begin
            case (cx)
                5'd9:  ch = 4'd13;          // T
                5'd10: ch = bcdt[7:4];
                5'd11: ch = bcdt[3:0];
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
                5'd9:  ch = B3;
                5'd10: ch = B2;
                5'd11: ch = B1;
                5'd12: ch = b0;
                5'd13: ch = 4'd10;
                5'd14: ch = 4'd11;
                5'd15: ch = 4'd12;
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
    wire locked = sel && cy == 4'd1 && !can_shift;      // P2 selected but the clutch is not pressed


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
    wire [10:0] r11 = {2'b0, p2, 3'b0} + {4'b0, p2, 1'b0} + {5'b0, p2};   // 11 * p2
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
    // 7. colour: text white (yellow when selected, red when P2 is locked), background dark blue, black outside the picture
    // ------------------------------------------------------------------
    assign rgb = !active ? 6'b00_00_00 :
                 text_on ? (locked ? 6'b11_00_00 : hl ? 6'b11_11_00 : 6'b11_11_11) :
                 in1     ? 6'b11_10_00 :
                 in2     ? 6'b01_11_11 :
                           6'b00_00_01;
endmodule
