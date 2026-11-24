`timescale 1ns / 1ps

module bj_btn_pulse #(
    parameter LOCK_MS = 10)(
    input  clk,
    input  rst_n,
    input  ms_tick,
    input  din,
    output pulse);

    reg       s0, s1, s1d;
    reg       lock;
    reg [5:0] cnt;

    wire rise = s1 & ~s1d;
    assign pulse = rise & ~lock;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0 <= 0; s1 <= 0; s1d <= 0;
            lock <= 0; cnt <= 0;
        end
        else begin
            s0  <= din;
            s1  <= s0;
            s1d <= s1;

            if (lock) begin
                if (s1)
                    cnt <= 0;
                else if (ms_tick) begin
                    if (cnt == LOCK_MS - 1) begin
                        lock <= 0;
                        cnt  <= 0;
                    end
                    else cnt <= cnt + 1;
                end
            end
            else if (rise)
                lock <= 1;
        end
    end
endmodule

