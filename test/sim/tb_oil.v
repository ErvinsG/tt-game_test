// Gearbox oil counter test (Icarus Verilog). Run from repo root:
//   iverilog -g2005 -o /tmp/tb_oil.vvp test/sim/tb_oil.v src/game_core.v src/ip_debounce.v src/ip_tick.v src/ip_div.v src/ip_bin2bcd.v src/ip_font.v src/ip_polar.v src/pwm.v && vvp /tmp/tb_oil.vvp
`timescale 1ns/1ps
module tb_oil;
  reg clk=0, rst_n=0;
  reg left=0,right=0,up=0,down=0,clutch=0;
  wire frame; wire active = 1'b0; wire [5:0] rgb; wire pwm_out;
  reg [7:0] fc=0; assign frame=(fc==199);
  always #5 clk=~clk;
  always @(posedge clk) fc <= (fc==199)?0:fc+1;
  game_core #(.DB(4),.STEP(4),.HFRAMES(3)) core(.clk(clk),.rst_n(rst_n),.left(left),.right(right),.up(up),.down(down),.clutch(clutch),
      .x(10'd0),.y(10'd0),.active(active),.frame(frame),.rgb(rgb),.pwm_out(pwm_out));
  integer errors=0;
  task frames(input integer n); integer i; begin for(i=0;i<n;i=i+1) @(posedge frame); end endtask
  task check(input cond, input [255:0] msg); begin if(!cond) begin errors=errors+1; $display("FAIL: %0s", msg); end else $display("ok:   %0s", msg); end endtask
  initial begin
    repeat(10) @(posedge clk); rst_n=1; frames(2);
    check(core.hours==100, "hours = 100 after reset");
    frames(30); check(core.hours<100 && core.hours>85, "counts down while the motor runs");
    // stop the motor: hours must freeze
    left=1; frames(1); left=0; frames(1);
    repeat(45) begin down=1; frames(1); down=0; frames(1); end
    check(core.p1==0, "motor at 0 rpm");
    begin : frz integer h; h=core.hours; frames(30); check(core.hours==h, "counter frozen at 0 rpm"); end
    // restart the motor, run to 0
    repeat(40) begin up=1; frames(1); up=0; frames(1); end
    frames(400);
    check(core.hours==0, "hours reach 0");
    check(core.oil_low==1, "oil lamp condition on");
    frames(300); check(core.hours==0, "stays at 0 until refilled");
    // pressing clutch refills
    clutch=1; frames(1);
    check(core.refill==1, "clutch press starts the refill animation");
    clutch=0; frames(10);
    check(core.refill==1 && core.hours==0, "animation running, hours not reset yet");
    begin : fin integer n; n=0; while (core.refill && n<400) begin @(posedge frame); n=n+1; end
      #1000; check(core.refill==0 && core.hours==100, "animation done, hours back to 100");
      check(n>120 && n<160, "animation lasts about 150 pictures"); end
    // clutch while oil is fine must not trigger the animation
    clutch=1; frames(2); clutch=0;
    check(core.refill==0, "clutch with oil OK does nothing");
    $display("errors=%0d", errors); $finish;
  end
endmodule
