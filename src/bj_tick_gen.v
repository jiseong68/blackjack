`timescale 1ns / 1ps

module bj_tick_gen #(
    parameter CYCLES = 100000,
    parameter W      = 17)(
    input      clk,
    input      rst_n,
    output reg tick);

    reg [W-1:0] c;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c    <= 0;
            tick <= 0;
        end
        else if (c == CYCLES - 1) begin
            c    <= 0;
            tick <= 1;
        end
        else begin
            c    <= c + 1;
            tick <= 0;
        end
    end
endmodule
