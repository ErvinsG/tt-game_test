// The game core: a wolf that you move around a 20x20 grid with a 4-way joystick.
//
// Two coordinate systems meet here:
//   * grid units   - the cell the wolf is in, 0..19 (5 bits each), px/py below
//   * screen pixels - the beam position the VGA shell hands us, x/y (10 bits)
// Everything the game decides is done in grid units; the drawing step only scales a
// cell index up to pixels and asks ip_rect "is the beam inside this cell?".
`default_nettype none

module game_core #(
    parameter DB   = 500000,     // debounce time in clocks, 20 ms at 25 MHz
    parameter GRID = 20,         // grid is GRID x GRID cells
    parameter CW   = 32,         // cell width  in pixels (640 / 20)
    parameter CH   = 24,         // cell height in pixels (480 / 20)
    parameter MOVE = 8           // move one cell every MOVE pictures while a button is held
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        left,      // raw buttons, they bounce
    input  wire        right,
    input  wire        up,
    input  wire        down,
    input  wire [9:0]  x,         // column of the pixel being drawn (screen pixels)
    input  wire [9:0]  y,         // row    of the pixel being drawn
    input  wire        active,    // high inside the visible 640x480 picture
    input  wire        frame,     // one clock pulse per picture
    output wire [5:0]  rgb        // {R[1:0], G[1:0], B[1:0]}
);
    wire left_c, right_c, up_c, down_c;
    ip_debounce #(.N(DB)) db_left  (.clk(clk), .rst_n(rst_n), .noisy(left),  .clean(left_c));
    ip_debounce #(.N(DB)) db_right (.clk(clk), .rst_n(rst_n), .noisy(right), .clean(right_c));
    ip_debounce #(.N(DB)) db_up    (.clk(clk), .rst_n(rst_n), .noisy(up),    .clean(up_c));
    ip_debounce #(.N(DB)) db_down  (.clk(clk), .rst_n(rst_n), .noisy(down),  .clean(down_c));

    // ------------------------------------------------------------------
    // 2. one "step" pulse every MOVE pictures, so the wolf does not fly
    //    across the whole grid in a fraction of a second.
    // ------------------------------------------------------------------
    wire step;
    ip_tick #(.DIV(MOVE)) move_tick (.clk(clk), .rst_n(rst_n), .en(frame), .tick(step));

    // ------------------------------------------------------------------
    // 3. the game state, in grid units (0..GRID-1)
    // test comment
    // ------------------------------------------------------------------
    reg [4:0] px, py;

    always @(posedge clk) begin
        if (!rst_n) begin
            px <= 0; // GRID / 2
            py <= 0;
        end else if (step) begin
            // independent x and y updates, so pressing two buttons moves diagonally
            if (left  && !right)      px <= (px > 0)      ? px - 5'd1 : px;
            else if (right && !left)  px <= (px < GRID-1) ? px + 5'd1 : px;

            if (up    && !down)       py <= (py > 0)      ? py - 5'd1 : py;
            else if (down  && !up)    py <= (py < GRID-1) ? py + 5'd1 : py;
        end
    end

    // ------------------------------------------------------------------
    // 4. translate the cell index to pixels, and reuse ip_rect to say
    //    "is the pixel being drawn inside the wolf's cell?"
    // ------------------------------------------------------------------
    wire [9:0] wx = {px, 5'b0};                 // px * CW  (CW == 32)
    wire [9:0] wy = (py << 4) + (py << 3);      // py * CH  (CH == 24)

    wire wolf_hit;
    ip_rect u_wolf (
        .x(x), .y(y), .rx(wx), .ry(wy),
        .rw(CW), .rh(CH), .hit(wolf_hit)
    );

    // grid lines sit on every cell boundary. With CW/CH constants these are cheap
    // comparisons; the whole 640x480 picture is exactly 20x20 cells.
    wire on_grid = 1'b0; //(x % CW == 0) || (y % CH == 0);

    // ------------------------------------------------------------------
    // 5. draw: wolf white, grid lines dim blue, everything else dark blue.
    //    Always punch black outside the visible picture.
    // ------------------------------------------------------------------
    assign rgb = !active  ? 6'b00_00_00 :
                 wolf_hit ? 6'b11_11_11 :
                 on_grid  ? 6'b00_00_10 :
                            6'b00_00_01;
endmodule
