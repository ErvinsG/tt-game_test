// Grid chase: a 20 x 20 field (cells of 32 x 24 px), you (dark green) hunt a runaway square (yellow).
//
//   * The human square moves one cell on every game tick while a direction button (up/down/left/right) is held.
//     Two buttons at once move diagonally. A game tick is MOVE pictures (default 8 -> 7.5 moves per second).
//   * The yellow square runs away. It moves on every 3rd game tick, one cell: along the axis where you are farther
//     away, sliding along a wall when that way is blocked. In one move out of four it steps in a random direction
//     instead (a 16 bit LFSR picks it), so it is not completely predictable.
//   * Fog of war: only a small window of cells around you is visible: you stand in its middle cell, it follows you
//     and stays on the map. The rest of the field is grey fog, so the yellow square can hide in it. The window starts
//     at 3 x 3. The buy button (and 4 catches, which it spends) makes it 5 x 5, and again 7 x 7. A cyan square under
//     the tally in the top left shows each upgrade you have.
//   * Both squares are 0.8 of a cell (26 x 20 px) so they stay inside their cell.
//   * When both squares end up in the same cell you have caught it: the catch counter goes up (one golden line
//     per catch in the top left corner, up to 31), that cell turns dark blue (the latest catch stays marked) and
//     the yellow square respawns on the other side of the field, at least 5 columns away, at a random row.
//     The game goes on. Reset starts again from zero catches.
//
// Screen coordinates: cell column = x / 32 = x[9:5]; the cell row is counted line by line (480 / 24 = 20 rows),
// because dividing y by 24 would cost more than two small counters.
`default_nettype none

module game_core #(
    parameter MOVE = 8,          // pictures per game tick
    parameter COST = 4           // catches (coins) per fog upgrade
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
    reg [3:0] mvc;
    reg [1:0] rc;
    wire tick  = frame && (mvc == MOVE - 1);
    wire rtick = tick && (rc == 2'd2);
    always @(posedge clk) begin
        if (!rst_n) begin
            mvc <= 4'd0;
            rc  <= 2'd0;
        end else if (frame) begin
            mvc <= tick ? 4'd0 : mvc + 4'd1;
            if (tick) rc <= (rc == 2'd2) ? 2'd0 : rc + 2'd1;
        end
    end

    // random numbers: 16 bit Fibonacci LFSR, x^16 + x^14 + x^13 + x^11 + 1, runs every clock
    reg [15:0] lfsr;
    always @(posedge clk) begin
        if (!rst_n) lfsr <= 16'hACE1;
        else        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
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
    wire       buy_ok = buy_c && !buy_d && (catches >= COST) && (level != 2'd2);   // a press with enough coins
    reg [4:0]  bx, by;        // the cell of the latest catch (it stays dark blue); column 31 = none yet

    // where the walker respawns: on the other half of the field (columns 14..19 or 0..5), random row
    wire [2:0] r3  = lfsr[7:5];
    wire [2:0] r6  = (r3 > 3'd5) ? r3 - 3'd6 : r3;                       // 0..5
    wire [4:0] nx  = (px < 5'd10) ? 5'd14 + {2'b00, r6} : {2'b00, r6};   // at least 5 columns away from the human
    wire [4:0] r5  = lfsr[12:8];
    wire [4:0] ny  = (r5 < 5'd20) ? r5 : r5 - 5'd12;                     // 0..19

    // where does the walker want to go? Away from the human, along the axis with the larger distance.
    wire [5:0] ddx = {1'b0, rx} - {1'b0, px};          // signed differences, walker minus human
    wire [5:0] ddy = {1'b0, ry} - {1'b0, py};
    wire [4:0] adx = ddx[5] ? (5'd0 - ddx[4:0]) : ddx[4:0];
    wire [4:0] ady = ddy[5] ? (5'd0 - ddy[4:0]) : ddy[4:0];
    wire horiz  = (adx >= ady);                        // the human is farther away in x: run along x
    wire away_r = !ddx[5];                             // walker is right of (or level with) the human: go right
    wire away_d = !ddy[5];
    wire can_h  = away_r ? (rx < 5'd19) : (rx > 5'd0); // the wall does not block that step
    wire can_v  = away_d ? (ry < 5'd19) : (ry > 5'd0);
    wire use_h  = (horiz && can_h) || (!horiz && !can_v);   // when the best axis is blocked slide along the other one
    wire do_h   = use_h && can_h;
    wire do_v   = !use_h && can_v;
    wire rnd    = (lfsr[3:2] == 2'b00);                // one move in four is random

    always @(posedge clk) begin
        if (!rst_n) begin
            px <= 5'd3;  py <= 5'd10;
            rx <= 5'd16; ry <= 5'd10;
            chk <= 1'b0;
            catches <= 5'd0;
            level   <= 2'd0;
            buy_d   <= 1'b0;
            bx <= 5'd31; by <= 5'd31;
        end else begin
            chk   <= tick;                       // the positions are updated now, look at them next clock
            buy_d <= buy_c;
            // coins: +1 for a catch (up to 31), -COST for an upgrade (both can happen in the same clock)
            catches <= catches + {4'b0, gotcha && (catches != 5'd31)} - (buy_ok ? COST : 5'd0);
            if (buy_ok) level <= level + 2'd1;
            if (gotcha) begin                    // caught: mark the cell, respawn the walker
                bx <= px; by <= py;
                rx <= nx; ry <= ny;
            end
            if (tick) begin
                // independent x and y moves, so two buttons give a diagonal step
                if (left_c && !right_c)       px <= (px > 5'd0)  ? px - 5'd1 : px;
                else if (right_c && !left_c)  px <= (px < 5'd19) ? px + 5'd1 : px;
                if (up_c && !down_c)          py <= (py > 5'd0)  ? py - 5'd1 : py;
                else if (down_c && !up_c)     py <= (py < 5'd19) ? py + 5'd1 : py;
            end
            if (rtick) begin
                if (rnd) begin
                    case (lfsr[1:0])
                        2'd0: rx <= (rx > 5'd0)  ? rx - 5'd1 : rx;     // left
                        2'd1: rx <= (rx < 5'd19) ? rx + 5'd1 : rx;     // right
                        2'd2: ry <= (ry > 5'd0)  ? ry - 5'd1 : ry;     // up
                        2'd3: ry <= (ry < 5'd19) ? ry + 5'd1 : ry;     // down
                    endcase
                end else if (do_h) rx <= away_r ? rx + 5'd1 : rx - 5'd1;
                else if (do_v)     ry <= away_d ? ry + 5'd1 : ry - 5'd1;
            end
        end
    end

    // ------------------------------------------------------------------
    // 4. which cell is the beam in? column from x, row from two counters (24 lines per row)
    // ------------------------------------------------------------------
    reg [4:0] cy;             // cell row 0..19
    reg [4:0] yin;            // line inside the cell row 0..23
    always @(posedge clk) begin
        if (!rst_n || (x == 10'd639 && y == 10'd524)) begin   // end of the last blanking line: the next line is line 0
            cy  <= 5'd0;
            yin <= 5'd0;
        end else if (x == 10'd639) begin           // end of the visible part of a line: step to the next line
            if (yin == 5'd23) begin
                yin <= 5'd0;
                cy  <= cy + 5'd1;
            end else begin
                yin <= yin + 5'd1;
            end
        end
    end
    wire [4:0] cx  = x[9:5];
    wire [4:0] xin = x[4:0];

    // ------------------------------------------------------------------
    // 5. colour
    // ------------------------------------------------------------------
    // squares: 26 x 20 px inside the 32 x 24 cell (0.8 of the cell, centred)
    wire sq = (xin >= 5'd3) && (xin < 5'd29) && (yin >= 5'd2) && (yin < 5'd22);
    wire hum_here = (px == cx) && (py == cy);
    wire rng_here = (rx == cx) && (ry == cy);

    wire blue = (bx == cx) && (by == cy);             // the cell of the latest catch

    // catch counter: one golden line (4 px wide, 24 px tall) per catch, 8 px apart, top left corner, drawn over the fog
    wire [9:0] xm    = x - 10'd8;
    // fog upgrades bought: one cyan square (8 x 8 px) per level under the tally, y = 40..47
    wire       lvl_sq = (y[9:4] == 6'd2) && (y[3] == 1'b1) && (((x[9:4] == 6'd0) && (x[3] == 1'b1) && (level != 2'd0)) ||
                                                              ((x[9:4] == 6'd1) && (x[3] == 1'b1) && (level == 2'd2)));
    wire       tally = (x[9:3] != 7'd0) && (y[9:5] == 5'd0) && (y[4:3] != 2'd0) && !xm[2] && (xm[9:3] < {2'b00, catches});

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
                 tally            ? 6'b11_10_00 :     // coins: golden lines
                 lvl_sq           ? 6'b00_11_11 :     // fog upgrades: cyan squares
                 !in_win          ? ((x[2] ^ y[2]) ? 6'b10_10_10 : 6'b01_01_01) :   // fog: grey dither
                 (hum_here && sq) ? 6'b00_01_00 :     // human: dark green
                 (rng_here && sq) ? 6'b11_11_00 :     // walker: yellow
                 blue             ? 6'b00_00_10 :     // cell of the latest catch: dark blue
                 grid             ? 6'b01_01_01 :     // cell borders
                                    6'b00_00_00;      // clear field
endmodule
