`timescale 1ns / 1ps

module bj_seg(
    input      [3:0] code,
    output reg [7:0] seg_out);

    parameter seg0 = 8'b00000011;   parameter seg1 = 8'b10011111;
    parameter seg2 = 8'b00100101;   parameter seg3 = 8'b00001101;
    parameter seg4 = 8'b10011001;   parameter seg5 = 8'b01001001;
    parameter seg6 = 8'b01000001;   parameter seg7 = 8'b00011111;
    parameter seg8 = 8'b00000001;   parameter seg9 = 8'b00011001;
    parameter segE    = 8'b01100001;
    parameter segDash = 8'b11111101;
    parameter segP    = 8'b00110001;
    parameter segd    = 8'b10000101;
    parameter segC    = 8'b01100011;
    parameter segOff  = 8'b11111111;

    always @(*) begin
        case (code)
            4'd0  : seg_out = seg0;
            4'd1  : seg_out = seg1;
            4'd2  : seg_out = seg2;
            4'd3  : seg_out = seg3;
            4'd4  : seg_out = seg4;
            4'd5  : seg_out = seg5;
            4'd6  : seg_out = seg6;
            4'd7  : seg_out = seg7;
            4'd8  : seg_out = seg8;
            4'd9  : seg_out = seg9;
            4'd10 : seg_out = segE;
            4'd11 : seg_out = segDash;
            4'd12 : seg_out = segP;
            4'd13 : seg_out = segd;
            4'd14 : seg_out = segC;
            default : seg_out = segOff;
        endcase
    end
endmodule

