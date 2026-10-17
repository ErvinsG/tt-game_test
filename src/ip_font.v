// 5x7 font for the characters the display needs.
// ch: 0-9 digits, 10 R, 11 P, 12 M, 13 T, anything else blank.
// row: 0 (top) .. 6, anything else blank. bits: the 5 pixels of that row, leftmost pixel is the MSB.
// One flat case on {ch,row} with 5 bit results (no wide constants, no nested lookups).

module ip_font (
    input  wire [3:0]  ch,
    input  wire [2:0]  row,
    output reg  [4:0]  bits
);
    always @(*) begin
        case ({ch, row})
            7'd0: bits = 5'b01110;
            7'd1: bits = 5'b10001;
            7'd2: bits = 5'b10011;
            7'd3: bits = 5'b10101;
            7'd4: bits = 5'b11001;
            7'd5: bits = 5'b10001;
            7'd6: bits = 5'b01110;
            7'd8: bits = 5'b00100;
            7'd9: bits = 5'b01100;
            7'd10: bits = 5'b00100;
            7'd11: bits = 5'b00100;
            7'd12: bits = 5'b00100;
            7'd13: bits = 5'b00100;
            7'd14: bits = 5'b01110;
            7'd16: bits = 5'b01110;
            7'd17: bits = 5'b10001;
            7'd18: bits = 5'b00001;
            7'd19: bits = 5'b00010;
            7'd20: bits = 5'b00100;
            7'd21: bits = 5'b01000;
            7'd22: bits = 5'b11111;
            7'd24: bits = 5'b11110;
            7'd25: bits = 5'b00001;
            7'd26: bits = 5'b00001;
            7'd27: bits = 5'b01110;
            7'd28: bits = 5'b00001;
            7'd29: bits = 5'b00001;
            7'd30: bits = 5'b11110;
            7'd32: bits = 5'b00010;
            7'd33: bits = 5'b00110;
            7'd34: bits = 5'b01010;
            7'd35: bits = 5'b10010;
            7'd36: bits = 5'b11111;
            7'd37: bits = 5'b00010;
            7'd38: bits = 5'b00010;
            7'd40: bits = 5'b11111;
            7'd41: bits = 5'b10000;
            7'd42: bits = 5'b11110;
            7'd43: bits = 5'b00001;
            7'd44: bits = 5'b00001;
            7'd45: bits = 5'b10001;
            7'd46: bits = 5'b01110;
            7'd48: bits = 5'b00110;
            7'd49: bits = 5'b01000;
            7'd50: bits = 5'b10000;
            7'd51: bits = 5'b11110;
            7'd52: bits = 5'b10001;
            7'd53: bits = 5'b10001;
            7'd54: bits = 5'b01110;
            7'd56: bits = 5'b11111;
            7'd57: bits = 5'b00001;
            7'd58: bits = 5'b00010;
            7'd59: bits = 5'b00100;
            7'd60: bits = 5'b01000;
            7'd61: bits = 5'b01000;
            7'd62: bits = 5'b01000;
            7'd64: bits = 5'b01110;
            7'd65: bits = 5'b10001;
            7'd66: bits = 5'b10001;
            7'd67: bits = 5'b01110;
            7'd68: bits = 5'b10001;
            7'd69: bits = 5'b10001;
            7'd70: bits = 5'b01110;
            7'd72: bits = 5'b01110;
            7'd73: bits = 5'b10001;
            7'd74: bits = 5'b10001;
            7'd75: bits = 5'b01111;
            7'd76: bits = 5'b00001;
            7'd77: bits = 5'b00010;
            7'd78: bits = 5'b01100;
            7'd80: bits = 5'b11110; // R
            7'd81: bits = 5'b10001;
            7'd82: bits = 5'b10001;
            7'd83: bits = 5'b11110;
            7'd84: bits = 5'b10100;
            7'd85: bits = 5'b10010;
            7'd86: bits = 5'b10001;
            7'd88: bits = 5'b11110; // P
            7'd89: bits = 5'b10001;
            7'd90: bits = 5'b10001;
            7'd91: bits = 5'b11110;
            7'd92: bits = 5'b10000;
            7'd93: bits = 5'b10000;
            7'd94: bits = 5'b10000;
            7'd96: bits = 5'b10001; // M
            7'd97: bits = 5'b11011;
            7'd98: bits = 5'b10101;
            7'd99: bits = 5'b10101;
            7'd100: bits = 5'b10001;
            7'd101: bits = 5'b10001;
            7'd102: bits = 5'b10001;
            7'd104: bits = 5'b11111; // T
            7'd105: bits = 5'b00100;
            7'd106: bits = 5'b00100;
            7'd107: bits = 5'b00100;
            7'd108: bits = 5'b00100;
            7'd109: bits = 5'b00100;
            7'd110: bits = 5'b00100;
            default: bits = 5'b00000;
        endcase
    end
endmodule
