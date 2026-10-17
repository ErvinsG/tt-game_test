// Quick logic test for the buttons / parameters (Icarus Verilog), not part of the cocotb flow.
// Run from repo root:
//   iverilog -g2005 -o /tmp/tb_btn.vvp test/sim/tb_buttons.v src/game_core.v src/ip_debounce.v src/ip_tick.v src/ip_div.v src/ip_bin2bcd.v src/ip_font.v src/ip_polar.v src/pwm.v && vvp /tmp/tb_btn.vvp
`timescale 1ns/1ps
module tb_btn;
  reg clk=0, rst_n=0;
  reg left=0,right=0,up=0,down=0,clutch=0;
  wire hsync,vsync,active,frame; wire [9:0] x,y; wire [5:0] rgb; wire pwm_out;
  always #5 clk=~clk;
  // fast fake frame pulse (every 200 clocks) so the test runs quickly; x/y unused here
  reg [7:0] fc=0; assign frame=(fc==199); assign x=0; assign y=0; assign active=0; assign hsync=0; assign vsync=0;
  always @(posedge clk) fc <= (fc==199)?0:fc+1;
  game_core #(.DB(4),.STEP(4)) core(.clk(clk),.rst_n(rst_n),.left(left),.right(right),.up(up),.down(down),.clutch(clutch),
      .x(x),.y(y),.active(active),.frame(frame),.rgb(rgb),.pwm_out(pwm_out));
  task frames(input integer n); integer i; begin for(i=0;i<n;i=i+1) begin @(posedge frame); end end endtask
  task press_up; begin up=1; frames(1); up=0; frames(1); end endtask
  task show(input [255:0] tag); begin $display("%0s: sel=%b p1=%0d p2=%0d can_shift=%b clutch_c=%b", tag, core.sel, core.p1, core.p2, core.can_shift, core.clutch_c); end endtask
  initial begin
    repeat(10) @(posedge clk); rst_n=1;
    frames(2); show("reset");
    right=1; frames(1); right=0; frames(1); show("after Right");
    press_up; show("Up, no clutch (p1=40)");
    clutch=1; frames(1); press_up; show("Up, clutch held");
    press_up; show("Up again, clutch held");
    clutch=0; frames(1);
    left=1; frames(1); left=0; frames(1); show("after Left");
    // clutch held: walk P2 to the top, check clamp at 64, then back down to the 12 minimum
    right=1; frames(1); right=0; frames(1);
    clutch=1; frames(1);
    repeat(60) press_up; show("P2 after 60 Up presses (expect 64)");
    frames(2); $display("rpm1=%0d rpm2=%0d (expect %0d)", core.rpm1, core.rpm2, core.p1*300/core.p2);
    $display("r2=%0d  gear2 centre x=%0d", core.r2, core.g2x);
    repeat(60) begin down=1; frames(1); down=0; frames(1); end show("P2 after 60 Down presses (expect 12)");
    // at 0 rpm no clutch is needed
    clutch=0; left=1; frames(1); left=0; frames(1);
    repeat(45) begin down=1; frames(1); down=0; frames(1); end show("P1 down to 0");
    right=1; frames(1); right=0; frames(1);
    press_up; press_up; show("P2 at 0 rpm, no clutch, 2 Up (expect 14)");
    $finish;
  end
endmodule
