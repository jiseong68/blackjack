`timescale 1ns / 1ps

module blackjack_game #(
    parameter MS_CYCLES   = 100000,  
    parameter SCAN_CYCLES = 2000,   
    parameter LOCK_MS     = 10)(
    input        clk,
    input        rst_n,      
    input        btn_start,   // 새 게임 시작
    input        btn_hit,     // 카드 한 장 더
    input        btn_stand,   // 멈춤
    input        btn_bet_up,  // 베팅 늘리기 (BTNR)
    input        btn_bet_dn,  // 베팅 줄이기 (BTNL)
    input        sw_chips,    // 칩 화면 보기 (SW0)
    input        sw_deck,     // 남은 카드 수 보기 (SW1)
    input        sw_best,     // 최고 기록 보기 (SW2)
    output [7:0] seg,
    output [7:0] an,        
    output       led_turn,    // 플레이어 차례
    output       led_win,
    output       led_lose,
    output       led_draw,
    output       buzzer); 

    //-------------------------------------------------------------------------
    // 1) tick / 버튼
    //-------------------------------------------------------------------------
    wire ms_tick, scan_tick;
    bj_tick_gen #(.CYCLES(MS_CYCLES),   .W(17)) u_ms   (clk, rst_n, ms_tick);
    bj_tick_gen #(.CYCLES(SCAN_CYCLES), .W(12)) u_scan (clk, rst_n, scan_tick);

    wire start_raw, hit_raw, stand_raw, bet_up_p, bet_dn_p;
    wire start_p = start_raw & ~sw_chips;   
    wire hit_p   = hit_raw   & ~sw_chips;
    wire stand_p = stand_raw & ~sw_chips;
    bj_btn_pulse #(.LOCK_MS(LOCK_MS)) u_b0 (clk, rst_n, ms_tick, btn_start, start_raw);
    bj_btn_pulse #(.LOCK_MS(LOCK_MS)) u_b1 (clk, rst_n, ms_tick, btn_hit,   hit_raw);
    bj_btn_pulse #(.LOCK_MS(LOCK_MS)) u_b2 (clk, rst_n, ms_tick, btn_stand, stand_raw);
    bj_btn_pulse #(.LOCK_MS(LOCK_MS)) u_b3 (clk, rst_n, ms_tick, btn_bet_up, bet_up_p);
    bj_btn_pulse #(.LOCK_MS(LOCK_MS)) u_b4 (clk, rst_n, ms_tick, btn_bet_dn, bet_dn_p);

    //-------------------------------------------------------------------------
    // 2) 카드 생성 (C1)
    //-------------------------------------------------------------------------
    reg [15:0] lfsr;
    reg [3:0]  gap;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= 16'hACE1;
            gap  <= 4'd0;
        end
        else begin
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            gap  <= gap + 4'd1;
        end
    end

    reg [2:0] used [0:15];   // 카드 종류(0~12)별로 이미 나온 장수 (최대 4장)
    reg [5:0] deck_used;     // 지금까지 나온 카드 수 (0~52)
    wire      card_valid = (lfsr[3:0] < 4'd13) && (used[lfsr[3:0]] < 3'd4);   // 남아 있는 종류만 유효
    wire [3:0] rank       = lfsr[3:0] + 4'd1;           // 1 ~ 13 (A,2~10,J,Q,K)
    wire [3:0] card       = (rank > 4'd10) ? 4'd10 : rank;   // J,Q,K 는 10점
    wire       draw_ok    = (gap == 4'hF) && card_valid;

    //-------------------------------------------------------------------------
    // 3) FSM (C7)
    //-------------------------------------------------------------------------
    localparam S_IDLE   = 3'd0,
               S_DEAL   = 3'd1,   // 처음 2장씩 (플레이어, 딜러, 플레이어, 딜러)
               S_PLAYER = 3'd2,   // Hit / Stand 입력 대기
               S_P_HIT  = 3'd3,   // 플레이어 카드 1장 추가
               S_DEALER = 3'd4,   // 딜러 판단 (16 이하 Hit)
               S_D_HIT  = 3'd5,   // 딜러 카드 1장 추가
               S_RESULT = 3'd6,   // 결과 표시
               S_CHECK  = 3'd7,   // 블랙잭 확인 (E4)
               S_BET    = 4'd8;   // 베팅 (E3)

    reg [3:0] state, next_state;
    reg [4:0] p_sum, d_sum;      
    reg [1:0] deal_cnt;

    wire [4:0] p_next = p_sum + {1'b0, card};
    reg p_ace, d_ace;   // 손에 Ace(카드 값 1)가 있으면 1

    // Ace 를 11 로 쓰면 21 이하가 되는 경우(합계 <= 11)에만 +10
    wire [4:0] p_val = (p_ace && (p_sum <= 5'd11)) ? (p_sum + 5'd10) : p_sum;
    wire [4:0] d_val = (d_ace && (d_sum <= 5'd11)) ? (d_sum + 5'd10) : d_sum;
    
        // 딜러가 카드를 뽑기 전 대기 시간 (연출용)
    localparam [9:0] DEALER_DELAY_MS = 10'd800;   // 0.8초
    reg [9:0] dly;
    wire      dly_done = (dly >= DEALER_DELAY_MS);
        // 더블다운용 선언
    reg [9:0] chips;                      // 보유 칩 (E3 블록에서 옮겨 옴)
    reg [9:0] bet;                        // 이번 판 베팅 (E3 블록에서 옮겨 옴)
    reg       dbl;                        // 이번 판에 더블다운 했는지
    reg       p_hit_used;                 // 플레이어가 Hit 를 이미 했는지
    wire [9:0] bet_eff = dbl ? {bet[8:0], 1'b0} : bet;   // 실제 베팅 (더블이면 2배)
    wire       dbl_ok  = bet_dn_p && !sw_chips && !p_hit_used
                         && ({1'b0, chips} >= {bet, 1'b0});
    reg  sur;                                          // 이번 판에 포기했는지
    wire sur_ok = bet_up_p && !bet_dn_p && !sw_chips && !p_hit_used;   // BTNR, Hit 전에만

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dly <= 10'd0;
        else if (state != S_DEALER)
            dly <= 10'd0;                         
        else if (ms_tick && dly < 10'd1023)
            dly <= dly + 10'd1;                   
    end

    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

   
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE   : if (start_p) next_state = S_DEAL;

            S_DEAL   : if (draw_ok && deal_cnt == 2'd3) next_state = S_CHECK;

            S_CHECK  : if (p_val == 5'd21 || d_val == 5'd21) next_state = S_RESULT;
                       else                                  next_state = S_PLAYER;

            S_PLAYER : if (p_val == 5'd21)      next_state = S_DEALER;   // 21 이면 자동 Stand
                       else if (stand_p)        next_state = S_DEALER;
                       else if (hit_p)          next_state = S_P_HIT;
                       else if (dbl_ok)         next_state = S_P_HIT;
                       else if (sur_ok)         next_state = S_RESULT; 

            S_P_HIT  : if (draw_ok)
                           next_state = (p_next > 5'd21) ? S_RESULT : (dbl ? S_DEALER : S_PLAYER);

            S_DEALER : if (dly_done) next_state = (d_val < 5'd17) ? S_D_HIT : S_RESULT;

            S_D_HIT  : if (draw_ok) next_state = S_DEALER;
            
            

            S_RESULT : if (start_p) next_state = S_DEAL;

            default  : next_state = S_IDLE;
        endcase
    end

    // 합계 누적 (C3) + Ace 보유 표시 (E1)
    

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_sum    <= 5'd0;
            d_sum    <= 5'd0;
            deal_cnt <= 2'd0;
            p_ace    <= 1'b0;
            d_ace    <= 1'b0;
        end
        else if ((state == S_IDLE || state == S_RESULT) && start_p) begin
            p_sum    <= 5'd0;
            d_sum    <= 5'd0;
            deal_cnt <= 2'd0;
            p_ace    <= 1'b0;
            d_ace    <= 1'b0;
        end
        else if (draw_ok) begin
            case (state)
                S_DEAL  : begin
                              if (deal_cnt[0]) begin
                                  d_sum <= d_sum + {1'b0, card};
                                  if (card == 4'd1) d_ace <= 1'b1;
                              end
                              else begin
                                  p_sum <= p_sum + {1'b0, card};
                                  if (card == 4'd1) p_ace <= 1'b1;
                              end
                              deal_cnt <= deal_cnt + 2'd1;
                          end
                S_P_HIT : begin
                              p_sum <= p_next;
                              if (card == 4'd1) p_ace <= 1'b1;
                          end
                S_D_HIT : begin
                              d_sum <= d_sum + {1'b0, card};
                              if (card == 4'd1) d_ace <= 1'b1;
                          end
                default : ;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // 4) 승패 판정 (C5)
    //-------------------------------------------------------------------------
    wire p_bust = (p_sum > 5'd21);
    wire d_bust = (d_sum > 5'd21);

    wire win  = ~sur & ~p_bust & (d_bust | (p_val > d_val));
    wire lose =  sur |  p_bust | (~d_bust & (d_val > p_val));
    wire draw = ~win & ~lose;

    assign led_turn = (state == S_PLAYER);
    assign led_win  = (state == S_RESULT) & win;
    assign led_lose = (state == S_RESULT) & lose;
    assign led_draw = (state == S_RESULT) & draw;
    //-------------------------------------------------------------------------
    // E6) 연승 카운터 : 결과 상태에 막 들어온 첫 클럭에만 갱신
    //-------------------------------------------------------------------------
    reg [3:0] prev_state;
    reg [3:0] streak;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_state <= S_IDLE;
            streak     <= 4'd0;
        end
        else begin
            prev_state <= state;
            if (state == S_RESULT && prev_state != S_RESULT) begin
                if (win) begin
                    if (streak < 4'd9) streak <= streak + 4'd1;   // 이김: +1 (최대 9)
                end
                else if (lose)
                    streak <= 4'd0;                                // 짐: 0 으로
                // 비김: 그대로 유지
            end
        end
    end
    //-------------------------------------------------------------------------
    // 블랙잭 배당용: 이번 판이 처음 2장 21(블랙잭)로 시작했는지 기억
    //-------------------------------------------------------------------------
    reg p_bj;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            p_bj <= 1'b0;
        else if (state == S_DEAL)
            p_bj <= 1'b0;                          // 새 판이 시작되면 지움
        else if (state == S_CHECK)
            p_bj <= (p_val == 5'd21);              // 처음 2장 21 이면 1
    end
    //-------------------------------------------------------------------------
    // 더블다운/포기 상태 기억
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbl        <= 1'b0;
            p_hit_used <= 1'b0;
            sur        <= 1'b0;
        end
        else if (state == S_DEAL) begin
            dbl        <= 1'b0;             // 새 판이 시작되면 지움
            p_hit_used <= 1'b0;
            sur        <= 1'b0;
        end
        else begin
            if (state == S_PLAYER && dbl_ok) dbl <= 1'b1;
            if (state == S_PLAYER && sur_ok) sur <= 1'b1;
            if (state == S_P_HIT)            p_hit_used <= 1'b1;
        end
    end
    //-------------------------------------------------------------------------
    // E8) 실제 52장 덱: 뽑은 카드는 덱에서 빠지고, 다 쓰면 다시 섞음
    //-------------------------------------------------------------------------
    integer i;
    wire [3:0] ridx     = lfsr[3:0];
    wire       draw_use = draw_ok && (state == S_DEAL || state == S_P_HIT || state == S_D_HIT);
    wire       reshuffle = (deck_used >= 6'd52) ||
                           ((state == S_IDLE || state == S_RESULT) && start_p && deck_used >= 6'd40);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 16; i = i + 1) used[i] <= 3'd0;
            deck_used <= 6'd0;
        end
        else if (reshuffle) begin
            for (i = 0; i < 16; i = i + 1) used[i] <= 3'd0;
            deck_used <= 6'd0;
        end
        else if (draw_use) begin
            used[ridx] <= used[ridx] + 3'd1;
            deck_used  <= deck_used + 6'd1;
        end
    end
    //-------------------------------------------------------------------------
    // 최고 기록: 최고 연승, 최고 칩
    //-------------------------------------------------------------------------
    reg [3:0] best_streak;
    reg [9:0] best_chips;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            best_streak <= 4'd0;
            best_chips  <= 10'd100;
        end
        else begin
            if (streak > best_streak) best_streak <= streak;
            if (chips  > best_chips)  best_chips  <= chips;
        end
    end
    //-------------------------------------------------------------------------
    // 딜러 업카드: 카드 분배에서 딜러가 처음 받는 카드(deal_cnt == 1)를 기억
    //-------------------------------------------------------------------------
    reg [3:0] d_up;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            d_up <= 4'd0;
        else if (state == S_DEAL && draw_ok && deal_cnt == 2'd1)
            d_up <= card;
    end
    //-------------------------------------------------------------------------
    // 소리 효과: 결과 화면에 들어온 뒤 지난 시간(ms)으로 울릴지 결정 (1 이면 울림)
    //-------------------------------------------------------------------------
    reg [11:0] beep_t;  

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            beep_t <= 12'd0;
        else if (state == S_RESULT && prev_state != S_RESULT)
            beep_t <= 12'd0;                         
        else if (ms_tick && beep_t < 12'd2000)
            beep_t <= beep_t + 12'd1;
    end

    wire beep_on = (win  && (beep_t < 12'd300 || (beep_t >= 12'd500 && beep_t < 12'd800))) ||
                   (lose && (beep_t < 12'd1000)) ||
                   (draw && (beep_t < 12'd500));

    assign buzzer = (state == S_RESULT) && (prev_state == S_RESULT) && beep_on;
    //-------------------------------------------------------------------------
    // 플레이어가 마지막으로 받은 카드 (딜러 카드는 홀 카드가 드러나서 제외)
    //-------------------------------------------------------------------------
    reg [3:0] p_last;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            p_last <= 4'd0;
        else if (draw_ok && ((state == S_DEAL && !deal_cnt[0]) || state == S_P_HIT))
            p_last <= card;
    end
    //-------------------------------------------------------------------------
    // E3) 칩과 베팅
    //-------------------------------------------------------------------------
    wire [9:0]  bet_max    = (chips < 10'd10) ? 10'd10 : ((chips > 10'd100) ? 10'd100 : chips);
    wire [9:0]  win_amt    = p_bj ? (bet + (bet >> 1)) : bet_eff;     // 블랙잭이면 1.5배
    wire [9:0]  loss_amt   = sur ? (bet >> 1) : bet_eff;   // 포기하면 절반만 잃음
    wire [10:0] chips_plus = {1'b0, chips} + {1'b0, win_amt};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            chips <= 10'd100;
            bet   <= 10'd10;
        end
        else begin
          
            if (state == S_RESULT && prev_state != S_RESULT) begin
                if (win)
                    chips <= (chips_plus > 11'd990) ? 10'd990 : chips_plus[9:0];
                else if (lose)
                    chips <= (chips > loss_amt) ? (chips - loss_amt) : 10'd0;
            end
            else if (state == S_RESULT && start_p && chips == 10'd0)
                chips <= 10'd100;    // 파산하면 새로 지급

            // 베팅 조절
            if (state == S_IDLE || state == S_RESULT) begin
                if (bet > bet_max)
                    bet <= bet_max;
                else if (bet_up_p && bet < bet_max)
                    bet <= bet + 10'd10;
                else if (bet_dn_p && bet > 10'd10)
                    bet <= bet - 10'd10;
            end
        end
    end

    //-------------------------------------------------------------------------
    // 5) 7-segment 표시 (C6)   "P 17 d 20"
    //    
    //-------------------------------------------------------------------------
    wire [3:0] p_t, p_o, d_t, d_o;
    bin_to_bcd2 u_pb (p_val, p_t, p_o);
    bin_to_bcd2 u_db (d_val, d_t, d_o);

    wire p_dash = (state == S_IDLE);
    wire d_hide = (state == S_IDLE)   || (state == S_DEAL) ||
                  (state == S_PLAYER) || (state == S_P_HIT);

    wire [3:0] n6 = p_dash ? 4'd11 : ((p_t == 4'd0) ? 4'd15 : p_t);
    wire [3:0] n5 = p_dash ? 4'd11 : p_o;
    wire up_show = (state == S_PLAYER) || (state == S_P_HIT);   // 플레이어 차례에는 업카드만 공개

    wire [3:0] n2 = up_show ? ((d_up == 4'd10) ? 4'd1 : 4'd15) :
                    (d_hide ? 4'd11 : ((d_t == 4'd0) ? 4'd15 : d_t));
    wire [3:0] n1 = up_show ? ((d_up == 4'd10) ? 4'd0 : d_up) :
                    (d_hide ? 4'd11 : d_o);

     
    wire [3:0] ch_h, ch_t, ch_o, bt_h, bt_t, bt_o;
    bin_to_bcd3 u_cb (chips, ch_h, ch_t, ch_o);
    wire [9:0] bet_show = (state == S_IDLE || state == S_RESULT) ? bet : bet_eff;
    bin_to_bcd3 u_bb (bet_show, bt_h, bt_t, bt_o);

    wire [3:0] sc_h = (ch_h == 4'd0) ? 4'd15 : ch_h;
    wire [3:0] sc_t = (ch_h == 4'd0 && ch_t == 4'd0) ? 4'd15 : ch_t;
    wire [3:0] sb_h = (bt_h == 4'd0) ? 4'd15 : bt_h;
    wire [3:0] sb_t = (bt_h == 4'd0 && bt_t == 4'd0) ? 4'd15 : bt_t;

    wire [3:0] n4 = (p_last == 4'd0) ? 4'd15 : ((p_last == 4'd10) ? 4'd0 : p_last);

    
    wire [31:0] disp_game  = {4'd12, n6,   n5,   n4,   4'd13, n2,   n1,   streak};
    wire [31:0] disp_chips = {4'd14, sc_h, sc_t, ch_o,  4'd11, sb_h, sb_t, bt_o};

    wire        show_chips = sw_chips;
    wire [5:0] deck_left = 6'd52 - deck_used;
    wire [3:0] dk_h, dk_t, dk_o;
    bin_to_bcd3 u_dk ({4'd0, deck_left}, dk_h, dk_t, dk_o);
    wire [31:0] disp_deck = {4'd13, 4'd15, 4'd15, 4'd15, 4'd15, 4'd15, dk_t, dk_o};

    wire [3:0] bc_h, bc_t, bc_o;
    bin_to_bcd3 u_bc (best_chips, bc_h, bc_t, bc_o);
    wire [3:0] sbc_h = (bc_h == 4'd0) ? 4'd15 : bc_h;
    wire [3:0] sbc_t = (bc_h == 4'd0 && bc_t == 4'd0) ? 4'd15 : bc_t;

    
    wire [31:0] disp_best = {4'd15, best_streak, 4'd15, 4'd15, 4'd14, sbc_h, sbc_t, bc_o};

    wire [31:0] disp       = sw_deck ? disp_deck : (sw_best ? disp_best : (show_chips ? disp_chips : disp_game));

    reg [2:0] idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)         idx <= 3'd0;
        else if (scan_tick) idx <= idx + 3'd1;
    end

    wire [3:0] nib = disp[idx*4 +: 4];
    wire [7:0] seg_raw;
    bj_seg u_seg (nib, seg_raw);

    // 플레이어 손에 Ace가 있으면 플레이어 일의 자리 소수점 ON,
    // 딜러는 합계가 공개된 뒤 Ace가 있으면 딜러 일의 자리 소수점 ON
    wire dp_on = !show_chips && !sw_deck && !sw_best &&
                 (((idx == 3'd5) && p_ace) ||
                  ((idx == 3'd4) && p_last == 4'd1) ||
                  ((idx == 3'd1) && ((d_ace && !d_hide) || (up_show && d_up == 4'd1))));
    
    // 덱 화면: 왼쪽 4자리에 "CArd" 글자를 직접 표시
    reg [7:0] deck_letter;
    always @(*) begin
        case (idx[1:0])
            2'd3    : deck_letter = 8'b01100011;   // C  (idx 7)
            2'd2    : deck_letter = 8'b00010001;   // A  (idx 6)
            2'd1    : deck_letter = 8'b11110101;   // r  (idx 5)
            default : deck_letter = 8'b10000101;   // d  (idx 4)
        endcase
    end

    assign seg = (sw_deck && idx[2]) ? deck_letter :
                 (sw_best && idx == 3'd7) ? 8'b10010001 :  
                 (dp_on ? (seg_raw & 8'b11111110) : seg_raw);

    assign an = ~(8'b00000001 << idx);

endmodule


