`timescale 1ns / 1ps

module tb_blackjack_game;

    localparam MS = 10;

    // DUT 와 같은 상태값 (계층 참조 대신 복사)
    localparam S_IDLE   = 3'd0,
               S_DEAL   = 3'd1,
               S_PLAYER = 3'd2,
               S_P_HIT  = 3'd3,
               S_DEALER = 3'd4,
               S_D_HIT  = 3'd5,
               S_RESULT = 3'd6;

    reg  clk = 0, rst_n = 0;
    reg  btn_start = 0, btn_hit = 0, btn_stand = 0;
    wire [7:0] seg, an;
    wire led_turn, led_win, led_lose, led_draw;

    integer errors = 0;
    integer n_win = 0, n_lose = 0, n_draw = 0, n_bust = 0;

    blackjack_game #(.MS_CYCLES(MS), .SCAN_CYCLES(4), .LOCK_MS(2)) dut (
        .clk(clk), .rst_n(rst_n),
        .btn_start(btn_start), .btn_hit(btn_hit), .btn_stand(btn_stand),
        .seg(seg), .an(an),
        .led_turn(led_turn), .led_win(led_win),
        .led_lose(led_lose), .led_draw(led_draw));

    always #5 clk = ~clk;   // 100MHz

    //--------------------------------------------------------------------------
    // 모델: DUT 가 카드를 뽑는 순간(draw_ok)에 카드 값을 따로 누적
    //--------------------------------------------------------------------------
    integer m_p = 0, m_d = 0;

    always @(posedge clk) begin
        if ((dut.state == S_IDLE || dut.state == S_RESULT) && dut.start_p) begin
            m_p = 0;
            m_d = 0;
        end
        else if (dut.draw_ok) begin
            if (dut.state == S_DEAL || dut.state == S_P_HIT || dut.state == S_D_HIT) begin
                // C1: 카드는 항상 1 ~ 10
                if (dut.card < 1 || dut.card > 10) begin
                    $display("[FAIL] 카드 범위 오류: %0d", dut.card);
                    errors = errors + 1;
                end
                case (dut.state)
                    S_DEAL  : if (dut.deal_cnt[0]) m_d = m_d + dut.card;
                              else                 m_p = m_p + dut.card;
                    S_P_HIT : m_p = m_p + dut.card;
                    S_D_HIT : m_d = m_d + dut.card;
                endcase
            end
        end
    end

    //--------------------------------------------------------------------------
    // 보조 task
    //--------------------------------------------------------------------------
    task wait_clk(input integer n);
        begin repeat (n) @(posedge clk); end
    endtask

    task wait_state(input [2:0] s, input integer maxclk);
        integer t;
        begin
            t = 0;
            while (dut.state != s && t < maxclk) begin
                @(posedge clk);
                t = t + 1;
            end
        end
    endtask

    // 버튼을 50클럭 누르고 50클럭 뗀다 (LOCK_MS=2 -> 20클럭 이상 떼어야 다음 입력 인식)
    task press_start; begin btn_start = 1; wait_clk(50); btn_start = 0; wait_clk(50); end endtask
    task press_hit;   begin btn_hit   = 1; wait_clk(50); btn_hit   = 0; wait_clk(50); end endtask
    task press_stand; begin btn_stand = 1; wait_clk(50); btn_stand = 0; wait_clk(50); end endtask

    //--------------------------------------------------------------------------
    // 결과 검사
    //--------------------------------------------------------------------------
    task check_result;
        reg exp_win, exp_lose, exp_draw;
        integer n_led;
        begin
            if (dut.state != S_RESULT) begin
                $display("[FAIL] 결과 상태(S_RESULT)에 도달하지 못함 (state=%0d)", dut.state);
                errors = errors + 1;
            end
            else begin
                // 합계 계산 (C3)
                if (dut.p_sum !== m_p[4:0] || dut.d_sum !== m_d[4:0]) begin
                    $display("[FAIL] 합계 불일치 DUT P=%0d D=%0d / 모델 P=%0d D=%0d",
                             dut.p_sum, dut.d_sum, m_p, m_d);
                    errors = errors + 1;
                end

                // 딜러 규칙 (C4): 플레이어가 Bust 가 아니면 딜러는 17 이상까지 뽑았어야 함
                if (m_p <= 21 && m_d < 17) begin
                    $display("[FAIL] 딜러가 17 미만에서 멈춤 (D=%0d)", m_d);
                    errors = errors + 1;
                end
                // Bust 면 딜러는 더 뽑지 않음 (처음 2장 합 <= 20)
                if (m_p > 21 && m_d > 20) begin
                    $display("[FAIL] 플레이어 Bust 인데 딜러가 카드를 뽑음 (D=%0d)", m_d);
                    errors = errors + 1;
                end

                // 승패 판정 (C5)
                exp_win  = (m_p <= 21) && (m_d > 21 || m_p > m_d);
                exp_lose = (m_p > 21)  || (m_d <= 21 && m_d > m_p);
                exp_draw = !exp_win && !exp_lose;

                n_led = led_win;
                n_led = n_led + led_lose;
                n_led = n_led + led_draw;

                if (n_led != 1) begin
                    $display("[FAIL] 결과 LED 가 정확히 1개가 아님 (win=%b lose=%b draw=%b)",
                             led_win, led_lose, led_draw);
                    errors = errors + 1;
                end
                if (led_win !== exp_win || led_lose !== exp_lose || led_draw !== exp_draw) begin
                    $display("[FAIL] 승패 불일치 P=%0d D=%0d 기대(W%b L%b D%b) 실제(W%b L%b D%b)",
                             m_p, m_d, exp_win, exp_lose, exp_draw, led_win, led_lose, led_draw);
                    errors = errors + 1;
                end

                if (m_p > 21) n_bust = n_bust + 1;
                if (exp_win)  n_win  = n_win  + 1;
                if (exp_lose) n_lose = n_lose + 1;
                if (exp_draw) n_draw = n_draw + 1;

                $display("[INFO] P=%0d D=%0d -> %s", m_p, m_d,
                         exp_win ? "WIN" : (exp_lose ? "LOSE" : "DRAW"));
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // 한 판 진행.  mode: 0 = 랜덤, 1 = 항상 Stand, 2 = 항상 Hit
    //--------------------------------------------------------------------------
    task play_round(input integer mode);
        integer k;
        reg done;
        begin
            press_start;
            wait_state(S_PLAYER, 5000);

            if (dut.state != S_PLAYER) begin
                $display("[FAIL] 카드 분배 후 S_PLAYER 에 도달하지 못함");
                errors = errors + 1;
            end
            // 처음 2장 합은 2 ~ 20
            if (dut.p_sum < 2 || dut.p_sum > 20 || dut.d_sum < 2 || dut.d_sum > 20) begin
                $display("[FAIL] 초기 분배 합계 범위 오류 P=%0d D=%0d", dut.p_sum, dut.d_sum);
                errors = errors + 1;
            end

            done = 0;
            k    = 0;
            while (!done && k < 40) begin
                if (dut.state == S_RESULT)
                    done = 1;
                else if (dut.state == S_PLAYER) begin
                    if (mode == 1)
                        press_stand;
                    else if (mode == 2)
                        press_hit;
                    else if (dut.p_sum >= 17 || ($random & 1))
                        press_stand;
                    else
                        press_hit;
                    wait_clk(300);
                end
                else
                    wait_clk(100);   // 카드 뽑는 중 / 딜러 진행 중
                k = k + 1;
            end

            check_result;
        end
    endtask

    //--------------------------------------------------------------------------
    // 메인 시나리오
    //--------------------------------------------------------------------------
    integer i;

    initial begin
        $dumpfile("tb_blackjack_game.vcd");
        $dumpvars(0, tb_blackjack_game);

        // --- 0) 리셋 후 IDLE ---
        #100 rst_n = 1;
        wait_clk(20);
        if (dut.state != S_IDLE) begin
            $display("[FAIL] 리셋 후 S_IDLE 이 아님"); errors = errors + 1;
        end

        // --- 1) IDLE 에서 Hit/Stand 는 무시되어야 함 ---
        press_hit;
        press_stand;
        if (dut.state != S_IDLE) begin
            $display("[FAIL] IDLE 에서 Hit/Stand 가 무시되지 않음"); errors = errors + 1;
        end
        else $display("[PASS] IDLE 에서 Hit/Stand 무시");

        // --- 2) 항상 Stand 5판 ---
        for (i = 0; i < 5; i = i + 1) play_round(1);

        // --- 3) RESULT 에서 Hit/Stand 는 무시되어야 함 ---
        if (dut.state == S_RESULT) begin
            press_hit;
            press_stand;
            if (dut.state != S_RESULT) begin
                $display("[FAIL] RESULT 에서 Hit/Stand 가 무시되지 않음"); errors = errors + 1;
            end
            else $display("[PASS] RESULT 에서 Hit/Stand 무시");
        end

        // --- 4) 항상 Hit 10판 (Bust 또는 21 이 나올 때까지) ---
        for (i = 0; i < 10; i = i + 1) play_round(2);

        // --- 5) 랜덤 전략 60판 ---
        for (i = 0; i < 60; i = i + 1) play_round(0);

        // --- 6) 게임 중 리셋 ---
        press_start;
        wait_clk(20);
        rst_n = 0; wait_clk(5); rst_n = 1; wait_clk(5);
        if (dut.state != S_IDLE || dut.p_sum != 0 || dut.d_sum != 0) begin
            $display("[FAIL] 리셋 후 초기화되지 않음"); errors = errors + 1;
        end
        else $display("[PASS] 게임 중 리셋");

        // --- 요약 ---
        $display("---- 요약: WIN %0d / LOSE %0d / DRAW %0d (플레이어 Bust %0d) ----",
                 n_win, n_lose, n_draw, n_bust);
        if (n_win == 0 || n_lose == 0 || n_bust == 0) begin
            $display("[WARN] 승/패/Bust 중 한 번도 나오지 않은 경우가 있음 (판 수를 늘려 보세요)");
        end

        if (errors == 0) $display("=== ALL PASS ===");
        else             $display("=== %0d ERROR(S) ===", errors);
        $finish;
    end

    // 안전장치
    initial begin
        #(100000000);
        $display("[FAIL] 시뮬레이션 시간 초과");
        $finish;
    end
endmodule