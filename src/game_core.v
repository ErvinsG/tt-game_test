// Grid chase: a 20 x 20 field (cells of 32 x 24 px), you (dark green) hunt a runaway square (yellow).
//
//   * The human square moves one cell on every game tick while a direction button (up/down/left/right) is held.
//     Two buttons at once move diagonally. A game tick is MOVE pictures (default 8 -> 7.5 moves per second).
//   * The yellow square runs away. It moves on every 3rd game tick, one cell: along the axis where you are farther
//     away, sliding along a wall when that way is blocked. In one move out of four it steps in a random direction
//     instead (a 13 bit LFSR picks it), so it is not completely predictable.
//   * Fog of war: only a small window of cells around you is visible: you stand in its middle cell, it follows you
//     and stays on the map. The rest of the field is grey fog, so the yellow square can hide in it. The window starts
//     at 3 x 3. The buy button (and 4 catches, which it spends) makes it 5 x 5, and again 7 x 7. (With LVLSQ = 1 a cyan
//     square under the tally in the top left shows each upgrade you have.)
//   * Last level: at 7 x 7 the buy button costs CUP (8) catches and wins the game: everything stops and a golden
//     trophy is drawn in the middle of the screen. (With LVLSQ = 1 the second cyan square turns gold when the cup is affordable.)
//   * Tile blockers: red cells nobody can enter (you stay where you are, the yellow square walks around them). There
//     are about BN0, BN1, BN2 of them at fog level 0, 1, 2 (3 x 3, 5 x 5, 7 x 7; currently 10, 35, 50) and they
//     jump to new places every BTICKS (22) game ticks, about 3 s. Which cells are blocked comes from a hash of (column, row,
//     epoch), so no positions are stored; the numbers are averages (usually within about +-30 %: 10 -> 5..15,
//     35 -> 27..44). Only blockers inside your clear window are visible.
//   * Idle timer: with an upgrade, a bar at the top of the screen runs down in TLEN pictures (60 per second, counted in game ticks). A catch (or buying an upgrade)
//     refills it. If it runs out the fog window shrinks by one level, you lose 3 coins (not below 0) and the bar starts again.
//   * Both squares are 0.8 of a cell (26 x 20 px) so they stay inside their cell.
//   * When both squares end up in the same cell you have caught it: the catch counter goes up (one golden line
//     per catch in the top left corner, up to 31), (with MARK = 1) that cell turns dark blue (the latest catch stays marked) and
//     the yellow square respawns on the other side of the field, at least 5 columns away, at a random row.
//     The game goes on. Reset starts again from zero catches.
//
// Screen coordinates: cell column = x / 32 = x[9:5]; the cell row is counted line by line (480 / 24 = 20 rows),
// because dividing y by 24 would cost more than two small counters.
`default_nettype none

module game_core #(
    parameter MOVE = 8,          // pictures per game tick
    parameter COST = 4,          // catches (coins) per fog upgrade
    parameter CUP  = 8,         // catches (coins) for the trophy at the last level
    parameter COINS0 = 0,       // coins at reset: 0 for the real game, more for testing (max 31)
    parameter BLOCKS = 1,        // 1 = tile blockers on, 0 = off
    parameter BN0 = 10,          // about this many blockers at fog level 0 (3 x 3)
    parameter BN1 = 35,          //                                 level 1 (5 x 5)
    parameter BN2 = 50,          //                                 level 2 (7 x 7)
    parameter BTICKS = 22,       // game ticks between two regenerations of the blockers (22 = about 3 s; max 32)
    parameter MARK   = 0,        // 1 = the cell of the latest catch stays dark blue (costs 10 flip-flops and ~6 % of a 1x1 tile)
    parameter LVLSQ  = 0,        // 1 = cyan squares under the tally show the fog upgrades (~4 % of a 1x1 tile)
    parameter CUPBMP = 0,        // 1 = the trophy has handles (a 16 x 8 bitmap), 0 = a plain cup (~1.5 % of a 1x1 tile)
    parameter TLEN = 600         // idle timer in pictures, 60 per second (600 = 10 s). It counts game ticks: TLEN / MOVE of them (max 127).
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        left,      // raw buttons, they bounce
    input  wire        right,
    input  wire        up,
    input  wire        down,
    input  wire        buy,       // raw buy button: spend COST catches on a bigger fog window
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire        active,
    input  wire        frame,     // one pulse per picture
    output wire [5:0]  rgb        // {R[1:0], G[1:0], B[1:0]}
);
    // ------------------------------------------------------------------
    // 1. buttons, sampled once per picture
    // ------------------------------------------------------------------
    wire left_c, right_c, up_c, down_c, buy_c;
    ip_btn db_l (.clk(clk), .rst_n(rst_n), .tick(frame), .raw(left),  .clean(left_c));
    ip_btn db_r (.clk(clk), .rst_n(rst_n), .tick(frame), .raw(right), .clean(right_c));
    ip_btn db_u (.clk(clk), .rst_n(rst_n), .tick(frame), .raw(up),    .clean(up_c));
    ip_btn db_d (.clk(clk), .rst_n(rst_n), .tick(frame), .raw(down),  .clean(down_c));
    ip_btn db_b (.clk(clk), .rst_n(rst_n), .tick(frame), .raw(buy),   .clean(buy_c));

    // ------------------------------------------------------------------
    // 2. game tick every MOVE pictures; the random square moves on every 3rd tick
    // ------------------------------------------------------------------
    reg       won;                // the trophy has been bought: the game is over, everything stands still
    reg [2:0] mvc;                // counts pictures 0 .. MOVE-1 (MOVE <= 8)
    reg [1:0] rc;
    reg [2:0] seq;                // after a tick: 1..4 = blocker lookups one by one, 5 = commit the moves
    // verilator lint_off WIDTH
    wire tick   = frame && (mvc == MOVE - 1) && !won;   // MOVE - 1 is a 32 bit integer, mvc has 3 bits: fine for MOVE <= 8
    // verilator lint_on WIDTH
    wire commit = (seq == 3'd5);
    wire rtick  = commit && (rc == 2'd2);
    always @(posedge clk) begin
        if (!rst_n) begin
            mvc <= 3'd0;
            rc  <= 2'd0;
        end else if (frame) begin
            mvc <= tick ? 3'd0 : mvc + 3'd1;
        end
        if (commit) rc <= (rc == 2'd2) ? 2'd0 : rc + 2'd1;
    end

    // random numbers: 13 bit Fibonacci LFSR, x^13 + x^4 + x^3 + x + 1 (period 8191), runs every clock
    reg [12:0] lfsr;
    always @(posedge clk) begin
        if (!rst_n) lfsr <= 13'h0ACE;
        else        lfsr <= {lfsr[11:0], lfsr[12] ^ lfsr[3] ^ lfsr[2] ^ lfsr[0]};
    end

    // ------------------------------------------------------------------
    // 3. the two squares, in cell units 0..19
    // ------------------------------------------------------------------
    reg [4:0] px, py;         // human
    reg [4:0] rx, ry;         // walker

    // a catch: both squares in one cell, checked one clock after every game tick
    reg        chk;
    wire       same  = (px == rx) && (py == ry);
    wire       gotcha = chk && same;
    reg [4:0]  catches;       // coins: how many times the walker has been caught, minus what was spent (max 31)
    reg [1:0]  level;         // fog upgrades bought: 0 = 3 x 3, 1 = 5 x 5, 2 = 7 x 7
    reg        buy_d;
    // idle timer: counts pictures down while a fog upgrade is active. Every catch and every purchase refills it;
    // when it reaches zero the fog window shrinks by one level and the timer is refilled.
    localparam integer TTI = TLEN / MOVE;                   // the timer in game ticks (75 for 600 / 8)
    localparam [6:0] TT = (TTI > 127) ? 7'd127 : TTI[6:0];  // 7 bits: longer timers are cut to 127 ticks
    reg [6:0]  trem;
    wire       expire = tick && (level != 2'd0) && (trem == 7'd0);
    wire       buy_ok = buy_c && !buy_d && (catches >= COST) && (level != 2'd2);   // a press with enough coins
    // running out of time costs 3 coins, but never more than you have (a purchase in the same clock keeps priority)
    wire [1:0] lose = (catches >= 5'd3) ? 2'd3 : catches[1:0];
    wire       cup_ok  = (level == 2'd2) && (catches >= CUP) && !won;              // the trophy can be bought
    wire       cup_buy = buy_c && !buy_d && cup_ok;
    // what leaves the purse this clock: only one of the three can apply (buy_ok needs level < 2, cup_buy needs level 2)
    localparam [4:0] COST5 = COST[4:0];                 // the prices as 5 bit constants (no width warnings)
    localparam [4:0] CUP5  = CUP[4:0];
    wire [4:0] spend = buy_ok ? COST5 : cup_buy ? CUP5 : (expire ? {3'b0, lose} : 5'd0);
    reg [4:0]  bx, by;        // the cell of the latest catch (it stays dark blue); column 31 = none yet

    // where the walker respawns: on the other half of the field (columns 14..19 or 0..5), random row
    wire [2:0] r3  = lfsr[7:5];
    wire [2:0] r6  = (r3 > 3'd5) ? r3 - 3'd6 : r3;                       // 0..5
    wire [4:0] nx  = (px < 5'd10) ? 5'd14 + {2'b00, r6} : {2'b00, r6};   // at least 5 columns away from the human
    wire [4:0] r5  = lfsr[12:8];
    wire [4:0] ny  = (r5 < 5'd20) ? r5 : r5 - 5'd12;                     // 0..19

    // ---- tile blockers: a cell is blocked when hash(column, row, epoch) is below a level dependent threshold.
    // The epoch counts regenerations: 16 different patterns, then the first one comes back (after about 48 s).
    reg [4:0] tcnt;                                // game ticks since the last regeneration
    reg [3:0] epoch;
    // thresholds on the 8 bit hash: n * 256 / 400 gives about n of the 400 cells (10 -> 6, 35 -> 22, 50 -> 32)
    localparam integer BI0 = (BN0 * 256 + 200) / 400;
    localparam integer BI1 = (BN1 * 256 + 200) / 400;
    localparam integer BI2 = (BN2 * 256 + 200) / 400;
    localparam [7:0] BT0 = BI0[7:0];
    localparam [7:0] BT1 = BI1[7:0];
    localparam [7:0] BT2 = BI2[7:0];
    wire [7:0] bthr = (level == 2'd0) ? BT0 : (level == 2'd1) ? BT1 : BT2;
    // The hash: spread (column, row, epoch) over 10 bits with shifts and XORs (cheap: no adders), then ONE AND round,
    // t ^= (t << 1) & (t >> 5), which makes it non-linear. The shifts were picked by a search so that the blocked cells
    // look random for the 16 epochs: they do not clump, and a regeneration changes most of them (Python model).
    function [7:0] bhash(input [4:0] ax, input [4:0] ay, input [3:0] e);
        reg [9:0] t;
        begin
            t = ({5'd0, ax} << 4) ^ ({5'd0, ay} << 1) ^ ({6'd0, e} << 8) ^ ({6'd0, e} << 5) ^ ({5'd0, ax} << 8) ^ ({5'd0, ay} << 6);
            t = t ^ (t << 1) ^ (t >> 8);
            t = t ^ ((t << 1) & (t >> 5));
            bhash = t[9:2];
        end
    endfunction

    // the cell row and the line inside it: 24 = 8 x 3, so y / 24 = (y / 8) / 3 and y % 24 = ((y / 8) % 3) * 8 + y % 8
    wire [5:0] y8 = y[8:3];                        // 0..59 while the picture is drawn
    // verilator lint_off WIDTH
    wire [4:0] cy  = y8 / 6'd3;                    // the quotient is 0..19 and the remainder 0..2: the upper bits are always 0
    wire [1:0] y3  = y8 % 6'd3;
    // verilator lint_on WIDTH
    wire [4:0] yin = {y3, y[2:0]};
    wire [4:0] cx  = x[9:5];
    wire [4:0] xin = x[4:0];

    // ONE hash unit serves every lookup. During the picture it answers for the beam's cell (seq = 0). After each game
    // tick (which starts in the blanking, so the picture does not need it) it answers four questions in a row, one per
    // clock, and the answers are kept: seq 1 = the human's target cell, 2 / 3 = the walker's horizontal / vertical
    // escape cell, 4 = the walker's random step. The moves are decided at seq 5. A square may always enter the cell of
    // the other one (that is a catch), so that cell is never reported as blocked.
    reg       hbk, bh, bv, rbk;                    // answers: human target, walker horizontal, vertical, random step
    reg [3:0] rl;                                   // the random numbers for this move, taken at the tick

    // where does the human go? one step in the pressed direction(s), unless that cell is blocked
    // (walking onto the yellow square is fine: that is a catch)
    wire       hl_ = left_c && !right_c, hr_ = right_c && !left_c, hu_ = up_c && !down_c, hd_ = down_c && !up_c;
    wire [4:0] htx = hl_ ? ((px != 5'd0) ? px - 5'd1 : px) : hr_ ? ((px != 5'd19) ? px + 5'd1 : px) : px;
    wire [4:0] hty = hu_ ? ((py != 5'd0) ? py - 5'd1 : py) : hd_ ? ((py != 5'd19) ? py + 5'd1 : py) : py;
    
    // where does the walker want to go? Away from the human, along the axis with the larger distance.
    wire [5:0] ddx = {1'b0, rx} - {1'b0, px};          // signed differences, walker minus human
    wire [5:0] ddy = {1'b0, ry} - {1'b0, py};
    wire [4:0] adx = ddx[5] ? (5'd0 - ddx[4:0]) : ddx[4:0];
    wire [4:0] ady = ddy[5] ? (5'd0 - ddy[4:0]) : ddy[4:0];
    wire horiz  = (adx >= ady);                        // the human is farther away in x: run along x
    wire away_r = !ddx[5];                             // walker is right of (or level with) the human: go right
    wire away_d = !ddy[5];
    wire [4:0] hcx = away_r ? rx + 5'd1 : rx - 5'd1;   // the cells one step away horizontally / vertically
    wire [4:0] vcy = away_d ? ry + 5'd1 : ry - 5'd1;
    wire can_h  = (away_r ? (rx != 5'd19) : (rx != 5'd0)) && !bh;   // neither a wall nor a blocker is in the way
    wire can_v  = (away_d ? (ry != 5'd19) : (ry != 5'd0)) && !bv;
    wire use_h  = (horiz && can_h) || (!horiz && !can_v);   // when the best axis is blocked slide along the other one
    wire do_h   = use_h && can_h;
    wire do_v   = !use_h && can_v;
    wire rnd    = (rl[3:2] == 2'b00);                  // one move in four is random
    wire [4:0] rtx = (rl[1:0] == 2'd0) ? ((rx != 5'd0) ? rx - 5'd1 : rx) : (rl[1:0] == 2'd1) ? ((rx != 5'd19) ? rx + 5'd1 : rx) : rx;
    wire [4:0] rty = (rl[1:0] == 2'd2) ? ((ry != 5'd0) ? ry - 5'd1 : ry) : (rl[1:0] == 2'd3) ? ((ry != 5'd19) ? ry + 5'd1 : ry) : ry;

    wire [4:0] qx = (seq == 3'd1) ? htx : (seq == 3'd2) ? hcx : (seq == 3'd3) ? rx  : (seq == 3'd4) ? rtx : cx;
    wire [4:0] qy = (seq == 3'd1) ? hty : (seq == 3'd2) ? ry  : (seq == 3'd3) ? vcy : (seq == 3'd4) ? rty : cy;
    wire [4:0] ex = (seq == 3'd1) ? rx : px;        // the cell that is never blocked
    wire [4:0] ey = (seq == 3'd1) ? ry : py;
    wire       qb = (BLOCKS != 0) && (bhash(qx, qy, epoch) < bthr) && !((qx == ex) && (qy == ey));

    always @(posedge clk) begin
        if (!rst_n) begin
            px <= 5'd3;  py <= 5'd10;
            rx <= 5'd16; ry <= 5'd10;
            chk <= 1'b0;
            catches <= COINS0;
            level   <= 2'd0;
            buy_d   <= 1'b0;
            trem    <= TT;
            won     <= 1'b0;
            bx <= 5'd31; by <= 5'd31;
            tcnt <= 5'd0;
            epoch <= 4'd0;
            seq <= 3'd0;
            hbk <= 1'b0; bh <= 1'b0; bv <= 1'b0; rbk <= 1'b0;
            rl <= 4'd0;
        end else begin
            chk   <= commit;                     // the positions are updated now, look at them next clock
            if (tick) begin seq <= 3'd1; rl <= lfsr[3:0]; end
            else if (seq != 3'd0) seq <= commit ? 3'd0 : seq + 3'd1;
            case (seq)
                3'd1: hbk <= qb;
                3'd2: bh  <= qb;
                3'd3: bv  <= qb;
                3'd4: rbk <= qb;
                default: ;
            endcase
            buy_d <= buy_c;
            // coins: +1 for a catch (up to 31), -COST for an upgrade, -CUP for the trophy, -3 when the timer runs out
            // (in practice they never fall in the same clock, but the sum is safe if they do)
            catches <= catches + {4'b0, gotcha && (catches != 5'd31)} - spend;
            if (cup_buy) won <= 1'b1;
            if (buy_ok)      level <= level + 2'd1;           // upgrade (wins if both happen at once)
            else if (expire) level <= level - 2'd1;           // timer ran out without a catch: the fog closes in
            if (gotcha || buy_ok || expire) trem <= TT;     // refill
            else if (tick && level != 2'd0) trem <= trem - 7'd1;
            if (gotcha) begin                    // caught: mark the cell, respawn the walker
                bx <= px; by <= py;
                rx <= nx; ry <= ny;
            end
            if (commit) begin
                if (tcnt == BTICKS - 1) begin                     // the blockers move to a new pattern every BTICKS game ticks
                    tcnt  <= 5'd0;
                    epoch <= epoch + 4'd1;
                end else begin
                    tcnt <= tcnt + 5'd1;
                end
                // the human: one step (two buttons at once give a diagonal step), unless that cell is blocked
                if (!hbk) begin
                    px <= htx;
                    py <= hty;
                end
            end
            if (rtick) begin
                if (rnd) begin
                    if (!rbk) begin                                   // a random step, not into a blocker
                        rx <= rtx;
                        ry <= rty;
                    end
                end else if (do_h) rx <= hcx;
                else if (do_v)     ry <= vcy;
            end
        end
    end

    // ------------------------------------------------------------------
    // 4. which cell is the beam in? column from x, row from y (no counters: y / 24 is a small divide by 3)
    // ------------------------------------------------------------------
    // ------------------------------------------------------------------
    // 5. colour
    // ------------------------------------------------------------------
    // squares: 26 x 20 px inside the 32 x 24 cell (0.8 of the cell, centred)
    wire sq = (xin >= 5'd3) && (xin < 5'd29) && (yin >= 5'd2) && (yin < 5'd22);
    wire hum_here = (px == cx) && (py == cy);
    wire rng_here = (rx == cx) && (ry == cy);

    wire blue = (MARK != 0) && (bx == cx) && (by == cy);             // the cell of the latest catch
    wire blk_here = qb && !rng_here;   // a blocker (never drawn under a square)

    // idle timer bar: top of the screen, y = 0..5, from x = 0; only with an upgrade. One game tick = MOVE = 8 pixels
    // of bar, so (x >> 3) < trem needs no subtractor. The empty track is TPX pixels long; the bar turns red in the last quarter.
    localparam [9:0] TPX  = TT * 8;
    localparam [6:0] TLOW = TT >> 2;
    wire       tbar_on = (level != 2'd0) && (y < 10'd6) && (x < TPX);
    wire       tbar    = tbar_on && (x[9:3] < trem);                       // the part that is left
    wire       tlow    = trem < TLOW;                                      // last quarter: red

    // catch counter: one golden line (4 px wide, 24 px tall) per catch, 8 px apart, top left corner, drawn over the fog
    // fog upgrades bought: one cyan square (8 x 8 px) per level under the tally, y = 40..47
    wire       lvl_row = (y[9:4] == 6'd2) && (y[3] == 1'b1);
    wire       lvl1_sq = lvl_row && (x[9:4] == 6'd0) && (x[3] == 1'b1) && (level != 2'd0);
    wire       lvl2_sq = lvl_row && (x[9:4] == 6'd1) && (x[3] == 1'b1) && (level == 2'd2);
    wire       lvl_sq  = (LVLSQ != 0) && (lvl1_sq || lvl2_sq);
    wire       tally = (x[9:3] != 7'd0) && (y[9:5] == 5'd0) && (y[4:3] != 2'd0) && !x[2] && (x[9:3] <= {2'b00, catches});

    // trophy: a 16 x 16 bitmap of which only the left half is stored (the right half is its mirror image);
    // every bit is 16 x 16 screen pixels, so the cup is 256 x 256 px in the middle of the screen (x 192.., y 112..)
    wire [5:0] cxx    = x[9:4] - 6'd12;
    wire [5:0] cyy    = y[9:4] - 6'd7;
    wire       in_cup = (cxx < 6'd16) && (cyy < 6'd16);
    wire [2:0] cm     = cxx[3] ? ~cxx[2:0] : cxx[2:0];
    reg  [7:0] crow;
    always @(*) begin
        case (cyy[3:0])
            4'd0:  crow = 8'b00111111;     //   rim
            4'd1:  crow = 8'b00111111;
            4'd2:  crow = 8'b11111111;     //   handle, top bar
            4'd3:  crow = 8'b10111111;
            4'd4:  crow = 8'b10111111;
            4'd5:  crow = 8'b11111111;     //   handle, bottom bar
            4'd6:  crow = 8'b00111111;
            4'd7:  crow = 8'b00011111;     //   bowl narrows
            4'd8:  crow = 8'b00001111;
            4'd9:  crow = 8'b00000111;
            4'd10: crow = 8'b00000011;     //   stem
            4'd11: crow = 8'b00000011;
            4'd12: crow = 8'b00000011;
            4'd13: crow = 8'b00000111;     //   foot
            4'd14: crow = 8'b00011111;
            default: crow = 8'b00111111;
        endcase
    end
    // the plain cup is the bitmap without its handle rows: how many columns from the outside are empty in each row
    wire [2:0] cthr = (cyy[3:0] < 4'd7) ? 3'd2 : (cyy[3:0] < 4'd10) ? cyy[2:0] - 3'd4 : (cyy[3:0] < 4'd13) ? 3'd6 :
                      (cyy[3:0] == 4'd13) ? 3'd5 : (cyy[3:0] == 4'd14) ? 3'd3 : 3'd2;
    wire cup_px = (CUPBMP != 0) ? (((crow << cm) & 8'h80) != 8'd0) : (cm >= cthr);

    // fog of war: a (2*half+1) x (2*half+1) window of cells with the human in the middle (kept on the map);
    // half = 1, 2, 3 for 3 x 3, 5 x 5, 7 x 7
    wire [2:0] half = {1'b0, level} + 3'd1;
    wire [4:0] vis  = {1'b0, half, 1'b1};                         // 3, 5 or 7
    wire [4:0] maxw = 5'd19 - {1'b0, half, 1'b0};                 // last possible window start: 17, 15 or 13
    wire [4:0] hlf5 = {2'b00, half};
    wire [4:0] wx = (px <= hlf5) ? 5'd0 : (px > 5'd19 - hlf5) ? maxw : px - hlf5;
    wire [4:0] wy = (py <= hlf5) ? 5'd0 : (py > 5'd19 - hlf5) ? maxw : py - hlf5;
    wire in_win = ((cx - wx) < vis) && ((cy - wy) < vis);
    wire grid   = (xin == 5'd0) || (yin == 5'd0);     // thin cell borders inside the clear window

    assign rgb = !active          ? 6'b00_00_00 :     // blanking
                 tbar             ? (tlow ? 6'b11_00_00 : 6'b00_11_11) :   // idle timer: cyan, red in the last 10 s
                 tbar_on          ? 6'b01_01_01 :     // idle timer: empty part of the bar
                 tally            ? 6'b11_10_00 :     // coins: golden lines
                 (won && in_cup)  ? (cup_px ? 6'b11_10_00 : 6'b00_00_00) :   // the trophy (black panel behind it)
                 lvl_sq           ? ((lvl2_sq && cup_ok) ? 6'b11_10_00 : 6'b00_11_11) :   // fog upgrades: cyan squares (2nd one gold: cup affordable)
                 !in_win          ? ((x[2] ^ y[2]) ? 6'b10_10_10 : 6'b01_01_01) :   // fog: grey dither
                 (hum_here && sq) ? 6'b00_01_00 :     // human: dark green
                 (rng_here && sq) ? 6'b11_11_00 :     // walker: yellow
                 blk_here         ? 6'b11_00_00 :     // tile blocker: red
                 blue             ? 6'b00_00_10 :     // cell of the latest catch: dark blue
                 grid             ? 6'b01_01_01 :     // cell borders
                                    6'b00_00_00;      // clear field
endmodule
