`timescale 1ns/1ps

module tb_bj_btn_pulse;
    reg clk = 0, rst_n = 0, din = 0;
    wire ms_tick, pulse;
    integer cnt, errors, i;

    always #5 clk = ~clk;   

    bj_tick_gen #(.CYCLES(20), .W(8)) u_ms(.clk(clk), .rst_n(rst_n), .tick(ms_tick));
    bj_btn_pulse #(.LOCK_MS(3)) dut(.clk(clk), .rst_n(rst_n), .ms_tick(ms_tick),
                                    .din(din), .pulse(pulse));

    
    always @(posedge clk) if (pulse) cnt <= cnt + 1;

    task wait_clk(input integer n);
        integer k;
        begin for (k = 0; k < n; k = k + 1) @(posedge clk); end
    endtask

    task check(input integer expect, input [255:0] name);
        begin
            if (cnt !== expect) begin
                errors = errors + 1;
                $display("FAIL %0s : pulses=%0d expected=%0d", name, cnt, expect);
            end
            else $display("PASS %0s : pulses=%0d", name, cnt);
        end
    endtask

    initial begin
        cnt = 0; errors = 0;
        wait_clk(5); rst_n = 1; wait_clk(5);

       
        cnt = 0;
        din = 1; wait_clk(200); din = 0; wait_clk(400);
        check(1, "T1 clean press");

        
        cnt = 0;
        din = 1; wait_clk(1000); din = 0; wait_clk(400);
        check(1, "T2 long hold");

        
        cnt = 0;
        for (i = 0; i < 6; i = i + 1) begin
            din = 1; wait_clk(4);
            din = 0; wait_clk(4);
        end
        din = 1; wait_clk(200); din = 0; wait_clk(400);
        check(1, "T3 bounce");

        
        cnt = 0;
        wait_clk(500);
        check(0, "T4 idle");

        
        din = 1; wait_clk(3);
        rst_n = 0; wait_clk(3); rst_n = 1; din = 0; wait_clk(100);
        cnt = 0; wait_clk(200);
        check(0, "T5 after reset");

        if (errors == 0) $display("ALL PASS tb_bj_btn_pulse");
        else             $display("FAIL tb_bj_btn_pulse: %0d errors", errors);
        $finish;
    end
endmodule