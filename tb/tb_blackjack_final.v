`timescale 1ns/1ps


module tb_blackjack_final;
    reg clk = 0, rst_n = 0;
    reg btn_start = 0, btn_hit = 0, btn_stand = 0, btn_bet_up = 0, btn_bet_dn = 0;
    reg sw_chips = 0, sw_deck = 0, sw_best = 0;
    wire [7:0] seg, an;
    wire led_turn, led_win, led_lose, led_draw, buzzer;

    integer errors = 0;
    integer i, k, r;
    reg [4:0] ps, ds;
    reg       exp_win, exp_lose;

    always #5 clk = ~clk;   

    blackjack_game #(.MS_CYCLES(20), .SCAN_CYCLES(8), .LOCK_MS(2)) dut (
        .clk(clk), .rst_n(rst_n),
        .btn_start(btn_start), .btn_hit(btn_hit), .btn_stand(btn_stand),
        .btn_bet_up(btn_bet_up), .btn_bet_dn(btn_bet_dn),
        .sw_chips(sw_chips), .sw_deck(sw_deck), .sw_best(sw_best),
        .seg(seg), .an(an),
        .led_turn(led_turn), .led_win(led_win), .led_lose(led_lose), .led_draw(led_draw),
        .buzzer(buzzer));

    localparam S_IDLE = 0, S_DEAL = 1, S_PLAYER = 2, S_P_HIT = 3,
               S_DEALER = 4, S_D_HIT = 5, S_RESULT = 6, S_CHECK = 7;

    task wait_clk(input integer n);
        integer q;
        begin for (q = 0; q < n; q = q + 1) @(posedge clk); end
    endtask

   
    task press_start; begin btn_start = 1; wait_clk(100); btn_start = 0; wait_clk(200); end endtask
    task press_hit;   begin btn_hit   = 1; wait_clk(100); btn_hit   = 0; wait_clk(200); end endtask
    task press_stand; begin btn_stand = 1; wait_clk(100); btn_stand = 0; wait_clk(200); end endtask
    task press_bet_up; begin btn_bet_up = 1; wait_clk(100); btn_bet_up = 0; wait_clk(200); end endtask

   
    task wait_player_or_result(input integer n);
        integer q;
        begin
            q = 0;
            while (dut.state != S_PLAYER && dut.state != S_RESULT && q < n) begin
                @(posedge clk); q = q + 1;
            end
        end
    endtask

    task wait_result(input integer n);
        integer q;
        begin
            q = 0;
            while (dut.state != S_RESULT && q < n) begin @(posedge clk); q = q + 1; end
        end
    endtask

    task check(input cond, input [255:0] name);
        begin
            if (cond) $display("PASS %0s", name);
            else begin errors = errors + 1; $display("FAIL %0s", name); end
        end
    endtask

    initial begin
       
        wait_clk(5); rst_n = 1; wait_clk(10);
        check(dut.state == S_IDLE && !led_turn && !led_win && !led_lose && !led_draw && !buzzer,
              "T1 reset -> IDLE, outputs off");

      
        sw_chips = 1; press_start; wait_clk(500);
        check(dut.state == S_IDLE, "T2 sw_chips blocks start");
        sw_chips = 0;

        
        press_start; wait_player_or_result(20000);
        check(dut.state == S_PLAYER || dut.state == S_RESULT, "T3 start -> PLAYER/RESULT");
        check(dut.p_sum >= 2 && dut.p_sum <= 20 || dut.state == S_RESULT, "T3b player sum sane");

        
        if (dut.state == S_PLAYER) check(led_turn == 1, "T4 led_turn=1 in PLAYER");
        else                       check(led_turn == 0, "T4 led_turn=0 in RESULT");

       
        if (dut.state == S_PLAYER) begin
            ps = dut.p_sum;
            press_hit; wait_player_or_result(20000);
            check(dut.p_sum > ps, "T5 hit adds a card");
        end

        
        if (dut.state == S_PLAYER) press_stand;
        wait_result(200000);
        check(dut.state == S_RESULT, "T6 reaches RESULT");
        check((led_win + led_lose + led_draw) == 1, "T6b exactly one result LED");
        check(!led_turn, "T6c led_turn=0 in RESULT");

       
        press_start; wait_clk(300);
        rst_n = 0; wait_clk(5); rst_n = 1; wait_clk(10);
        check(dut.state == S_IDLE, "T7 reset in game -> IDLE");

       
        for (r = 0; r < 30; r = r + 1) begin
            press_start; wait_player_or_result(20000);
            if (dut.state == S_PLAYER) press_stand;
            wait_result(200000);
            ps = dut.p_val; ds = dut.d_val;
            exp_win  = !dut.sur && !(dut.p_sum > 21) && ((dut.d_sum > 21) || (ps > ds));
            exp_lose =  dut.sur ||  (dut.p_sum > 21) || (!(dut.d_sum > 21) && (ds > ps));
            if (dut.state !== S_RESULT || led_win !== exp_win || led_lose !== exp_lose ||
                led_draw !== (!exp_win && !exp_lose)) begin
                errors = errors + 1;
                $display("FAIL T8 round %0d: p=%0d d=%0d win=%b lose=%b draw=%b",
                         r, ps, ds, led_win, led_lose, led_draw);
            end
            for (k = 0; k < 13; k = k + 1)
                if (dut.used[k] > 4) begin
                    errors = errors + 1;
                    $display("FAIL T8 round %0d: rank %0d used %0d times", r, k, dut.used[k]);
                end
            wait_clk(50);
        end
        $display("INFO T8 finished 30 rounds");

        if (errors == 0) $display("ALL PASS tb_blackjack_final");
        else             $display("FAIL tb_blackjack_final: %0d errors", errors);
        $finish;
    end

   
    initial begin
        #200000000;
        $display("FAIL watchdog timeout");
        $finish;
    end
endmodule