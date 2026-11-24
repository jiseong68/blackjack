`timescale 1ns / 1ps

module bin_to_bcd2(
    input  [4:0] bin,
    output [3:0] tens,
    output [3:0] ones);

    wire [4:0] ones5 = (bin >= 5'd30) ? (bin - 5'd30) :
                       (bin >= 5'd20) ? (bin - 5'd20) :
                       (bin >= 5'd10) ? (bin - 5'd10) : bin;

    assign tens = (bin >= 5'd30) ? 4'd3 :
                  (bin >= 5'd20) ? 4'd2 :
                  (bin >= 5'd10) ? 4'd1 : 4'd0;
    assign ones = ones5[3:0];
endmodule
//------------------------------------------------------------------------------
// 0~999 이진수 -> 백/십/일의 자리 (칩·베팅 표시용)
//------------------------------------------------------------------------------
module bin_to_bcd3(
    input  [9:0] bin,
    output [3:0] hun,
    output [3:0] ten,
    output [3:0] one);

    wire [9:0] q10  = bin / 10'd10;
    wire [9:0] r1   = bin % 10'd10;
    wire [9:0] r10  = q10 % 10'd10;
    wire [9:0] q100 = q10 / 10'd10;

    assign hun = q100[3:0];
    assign ten = r10[3:0];
    assign one = r1[3:0];
endmodule
