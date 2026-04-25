`default_nettype none

module TileGrowth(
    input logic clock, reset_n,
    input logic up, down, left, right,
    input logic color_sel, place, start,
    output logic data,
    output logic [7:0] count
);

    //16x16 grid of 1 of 4 colors
    //NOTE: Icarus does not support array slicing,
    //so the grid is defined by 2 seperate 16 long
    //arrays of 16 bit words
    logic [15:0] gridl [15:0]; // low bit  
    logic [15:0] gridh [15:0]; // high bit 

    logic [255:0] gridl_p, gridh_p;

    genvar j;
    generate
        for(j = 0; j < 16; j++) begin
            assign gridl_p[j*16 +: 16] = gridl[j];
            assign gridh_p[j*16 +: 16] = gridh[j];
        end
    endgenerate

    //Pre-game grid write
    logic pg_wr_en;
    logic [3:0] pg_wr_row, pg_wr_col;
    logic [1:0] pg_wr_data;

    //In-game grid write
    logic ig_wr_en;
    logic [3:0] ig_wr_row, ig_wr_col;
    logic [1:0] ig_wr_data;

    //Game Stage
    logic game_start;
    //logic frozen, game_done;
    logic game_done;

    //Cursor
    //logic [3:0] cursor_row, cursor_col;
    //logic [1:0] selected_color;

    //LFSR
    //logic [15:0] lfsr_val;
    logic lv2, lv3, lv5, lv8, lv12, lv15;
    logic lfsr_seed_en;
    logic [15:0] lfsr_seed;

    //blink the Cursor pre-game
    logic blink_state;
    logic [31:0] blink_counter;

    always_ff @(posedge clock, negedge reset_n) begin
        if(~reset_n) begin
            blink_counter <= 32'd0;
            blink_state   <= 1'b0;
        end
        else if (~game_start) begin
            blink_counter <= blink_counter + 32'd1;
            if(blink_counter == 32'h1FFFFF)
                blink_state <= ~blink_state;
        end
    end

    //write to the Grid
    always_ff @(posedge clock, negedge reset_n) begin
        if(~reset_n) begin
            for(int r = 0; r < 16; r++) begin
                gridl[r] <= 16'd0;
                gridh[r] <= 16'd0;
            end
        end
        else begin
            if(~game_start && pg_wr_en) begin
                gridl[pg_wr_row][pg_wr_col] <= pg_wr_data[0];
                gridh[pg_wr_row][pg_wr_col] <= pg_wr_data[1];
            end
            else if(game_start && ig_wr_en) begin
                gridl[ig_wr_row][ig_wr_col] <= ig_wr_data[0];
                gridh[ig_wr_row][ig_wr_col] <= ig_wr_data[1];
            end
        end
    end

    PreStartFSM pg (
        .clock, .reset_n,
        .up, .down, .left, .right,
        .color_sel, .place, .start,
        //.cursor_row, .cursor_col,
        //.selected_color,
        .game_start,
        .wr_en(pg_wr_en),
        .wr_row (pg_wr_row),
        .wr_col(pg_wr_col),
        .wr_data(pg_wr_data),
        .lfsr_seed_en,
        .lfsr_seed
    );

    InGameFSM ig (
        .clock, .reset_n,
        .game_start,
        .gridl_p, .gridh_p,
        //.lfsr_val,
        .lv2, .lv3, .lv5,
        .lv8, .lv12, .lv15,
        .wr_en(ig_wr_en),
        .wr_row(ig_wr_row),
        .wr_col(ig_wr_col),
        .wr_data(ig_wr_data),
        //.frozen,
        .done(game_done),
        .count
    );

    LFSR16 lfsr (
        .clock, .reset_n,
        .seed_en(lfsr_seed_en),
        .seed(lfsr_seed),
        //.val(lfsr_val)
        .lv2, .lv3, .lv5,
        .lv8, .lv12, .lv15
    );

    WS2812B_Driver ws2812b (
        .clock, .reset_n,
        .gridl_p, .gridh_p,
        .ws_data(data)
    );

endmodule : TileGrowth


module PreStartFSM(
    input logic clock, reset_n,
    input logic up, down, left, right,
    input logic color_sel, place, start,
    //output logic [3:0] cursor_row, cursor_col,
    //output logic [1:0] selected_color,
    output logic game_start,
    output logic wr_en,
    output logic [3:0] wr_row, wr_col,
    output logic [1:0] wr_data,
    output logic lfsr_seed_en,
    output logic [15:0] lfsr_seed
);

    logic [3:0] cursor_row, cursor_col;
    logic [1:0] selected_color;

    enum logic [2:0] {IDLE, MOVEUP, MOVEDOWN, MOVELEFT, 
                      MOVERIGHT, PLACE, START} cur_state, next_state;

    logic up_prev, down_prev, left_prev, right_prev;
    logic cs_prev, place_prev, start_prev;
    logic up_c, dn_c, lt_c, rt_c, cs_c, pl_c, st_c;

    always_ff @(posedge clock, negedge reset_n) begin
        if(~reset_n) begin
            up_prev <= 0;
            down_prev <= 0;
            left_prev <= 0;
            right_prev <= 0;
            cs_prev <= 0;
            place_prev <= 0;
            start_prev <= 0;
        end
        else begin
            up_prev <= up;
            down_prev <= down;
            left_prev <= left;
            right_prev <= right;
            cs_prev <= color_sel;
            place_prev <= place;
            start_prev <= start;
        end
    end

    always_comb begin
        up_c = up & ~up_prev;
        dn_c = down & ~down_prev;
        lt_c = left & ~left_prev;
        rt_c = right & ~right_prev;
        cs_c = color_sel & ~cs_prev;
        pl_c = place & ~place_prev;
        st_c = start & ~start_prev;
    end

    logic [31:0] counter;

    always_ff @(posedge clock, negedge reset_n) begin
        if(~reset_n) begin
            counter <= 32'd0;
        end
        else begin 
            counter <= counter + 32'd1;
        end
    end

    // Next-state logic
    always_comb begin
        case(cur_state)
            IDLE: begin
                if(up_c) next_state = MOVEUP;
                else if(dn_c) next_state = MOVEDOWN;
                else if(lt_c) next_state = MOVELEFT;
                else if(rt_c) next_state = MOVERIGHT;
                else if(pl_c) next_state = PLACE;
                else if(st_c) next_state = START;
                else next_state = IDLE;
            end
            MOVEUP: next_state = IDLE;
            MOVEDOWN: next_state = IDLE;
            MOVELEFT: next_state = IDLE;
            MOVERIGHT: next_state = IDLE;
            PLACE: next_state = IDLE;
            START: next_state = START;
            default: next_state = IDLE;
        endcase
    end

    // State register
    always_ff @(posedge clock, negedge reset_n) begin
        if(~reset_n) begin
            cur_state <= IDLE;
        end
        else begin
            cur_state <= next_state;
        end
    end

    // Output / datapath
    always_ff @(posedge clock, negedge reset_n) begin
        if(~reset_n) begin
            cursor_row <= 4'd7;
            cursor_col <= 4'd7;
            selected_color <= 2'd1;
            game_start <= 1'b0;
            wr_en <= 1'b0;
            wr_row <= 4'h0;
            wr_col <= 4'h0;
            wr_data <= 2'd0;
            lfsr_seed_en <= 1'b0;
            lfsr_seed <= 16'h0000;
        end
        else begin
            wr_en <= 1'b0;
            lfsr_seed_en <= 1'b0;
            case(cur_state)
                MOVEUP: cursor_row <= (cursor_row == 0) ? 4'd15 : cursor_row - 1;
                MOVEDOWN: cursor_row <= (cursor_row == 15) ? 4'd0  : cursor_row + 1;
                MOVERIGHT: cursor_col <= (cursor_col == 15) ? 4'd0  : cursor_col + 1;
                MOVELEFT: cursor_col <= (cursor_col == 0) ? 4'd15 : cursor_col - 1;
                PLACE: begin
                    wr_en <= 1'b1;
                    wr_row <= cursor_row;
                    wr_col <= cursor_col;
                    wr_data <= selected_color;
                    lfsr_seed <= lfsr_seed ^ counter[15:0];
                    lfsr_seed_en <= 1'b1;
                end
                START: game_start <= 1'b1;
                IDLE: begin
                    if(cs_c) begin
                        selected_color <= (selected_color == 2'd1) ? 2'd2 : 2'd1;
                    end
                end
                default: ;
            endcase
        end
    end

endmodule : PreStartFSM


module InGameFSM(
    input logic clock, reset_n,
    input logic game_start,
    input logic [255:0] gridl_p,
    input logic [255:0] gridh_p,
    //input logic [15:0] lfsr_val,
    input logic lv2, lv3, lv5, lv8, lv12, lv15,
    output logic wr_en,
    output logic [3:0] wr_row, wr_col,
    output logic [1:0] wr_data,
    //output logic frozen,
    output logic done,
    output logic [7:0] count
);

    //unpack the grid
    logic [15:0] gridl [15:0];
    logic [15:0] gridh [15:0];

    genvar i;

    generate 
        for(i = 0; i < 16; i++) begin
            assign gridl[i] = gridl_p[i*16 +: 16];
            assign gridh[i] = gridh_p[i*16 +: 16];
        end
    endgenerate

    enum logic [1:0] {FROZEN, STALL, SPREAD, DONE} cur_state, next_state;

    logic [31:0] stall_counter;
    //localparam STALL_MAX = 32'd500_0000; // synthesis
    localparam STALL_MAX = 32'd10;          // simulation

    logic [3:0] row, col;
    logic filled;

    logic [7:0] col1_count;

    //Random vars
    logic [3:0] spread;
    logic [1:0] dir;

    //assign spread = {lfsr_val[12], lfsr_val[2], lfsr_val[5], lfsr_val[15]};
    //assign dir    = {lfsr_val[8],  lfsr_val[3]};
    assign spread = {lv12, lv2, lv5, lv15};
    assign dir = {lv8, lv3};

    // Check whether every cell is non-zero
    always_comb begin
        filled = 1'b1;
        for(int r = 0; r < 16; r++)
            for(int c = 0; c < 16; c++)
                if((gridl[r][c] == 1'b0) && (gridh[r][c] == 1'b0)) begin
                    filled = 1'b0;
                end
    end

    // Next-state logic
    always_comb begin
        //frozen = 1'b0;
        done   = 1'b0;
        case(cur_state)
            FROZEN: begin
                if(game_start) next_state = STALL;
                else next_state = FROZEN;
                //frozen = 1'b1;
            end
            STALL: begin
                if(stall_counter == STALL_MAX) next_state = SPREAD;
                else next_state = STALL;
            end
            SPREAD: begin
                next_state = SPREAD;
                if(row == 4'd15 && col == 4'd15) begin
                    if(filled) next_state = DONE;
                    else       next_state = STALL;
                end
            end
            DONE: begin
                next_state = DONE;
                //frozen = 1'b1;
                done   = 1'b1;
            end
        endcase
    end

    // State register
    always_ff @(posedge clock, negedge reset_n) begin
        if(~reset_n) begin
            cur_state <= FROZEN;
        end
        else begin
            cur_state <= next_state;
        end
    end

    // Datapath
    always_ff @(posedge clock, negedge reset_n) begin
        if(~reset_n) begin
            stall_counter <= 0;
            row <= 0;
            col <= 0;
            col1_count <= 0;
            count <= 0;
            wr_en <= 0;
            wr_row <= 0;
            wr_col <= 0;
            wr_data <= 0;
        end
        else begin
            wr_en <= 0;
            case(cur_state)
                FROZEN: begin
                    stall_counter <= 0;
                end
                STALL: begin
                    stall_counter <= stall_counter + 1;
                    if(stall_counter == STALL_MAX) begin
                        stall_counter <= 0;
                        row <= 0;
                        col <= 0;
                        col1_count <= 0;
                    end
                end
                SPREAD: begin
                    if((gridh[row][col] == 1'b0) && (gridl[row][col] == 1'b1))
                        col1_count <= col1_count + 8'd1;

                    if(!((gridh[row][col] == 1'b0) && (gridl[row][col] == 1'b0))) begin
                        if(spread == 4'hA) begin
                            wr_en   <= 1'b1;
                            wr_data <= {gridh[row][col], gridl[row][col]};
                            case(dir)
                                2'b00: begin
                                    if(row < 4'd15 && (gridl[row+1][col] == 1'b0) &&
                                       (gridh[row+1][col] == 1'b0)) begin
                                        wr_row <= row + 4'd1;
                                        wr_col <= col;
                                    end
                                    else begin
                                        wr_en <= 1'b0;
                                    end
                                end
                                2'b01: begin
                                    if(col < 4'd15 &&
                                       (gridl[row][col+1] == 1'b0) &&
                                       (gridh[row][col+1] == 1'b0)) begin
                                        wr_row <= row;
                                        wr_col <= col + 4'd1;
                                    end
                                    else begin
                                        wr_en <= 1'b0;
                                    end
                                end
                                2'b10: begin
                                    if(col > 4'd0 &&
                                       (gridl[row][col-1] == 1'b0) &&
                                       (gridh[row][col-1] == 1'b0)) begin
                                        wr_row <= row;
                                        wr_col <= col - 4'd1;
                                    end
                                    else begin
                                        wr_en <= 1'b0;
                                    end
                                end
                                2'b11: begin
                                    if(row > 4'd0 &&
                                       (gridl[row-1][col] == 1'b0) &&
                                       (gridh[row-1][col] == 1'b0)) begin
                                        wr_row <= row - 4'd1;
                                        wr_col <= col;
                                    end
                                    else begin
                                        wr_en <= 1'b0;
                                    end
                                end
                            endcase
                        end
                    end

                    if(col == 4'd15) begin
                        col <= 0;
                        row <= row + 1;
                    end
                    else begin
                        col <= col + 1;
                    end

                    //update count
                    if(row == 4'd15 && col == 4'd15)
                        count <= col1_count;
                end

                DONE: begin
                    // wait for reset
                end
            endcase
        end
    end

endmodule : InGameFSM

module LFSR16(
    input logic clock, reset_n,
    input logic seed_en,
    input logic [15:0] seed,
    //output logic [15:0] val
    output logic lv2, lv3, lv5, lv8, lv12, lv15
);
    
    logic [15:0] val;
    logic in;
    
    assign in = val[15] ^ val[13] ^ val[12] ^ val[10];

    assign lv2 = val[2];
    assign lv3 = val[3];
    assign lv5 = val[5]; 
    assign lv8 = val[8];
    assign lv12 = val[12];
    assign lv15 = val[15];

    always_ff @(posedge clock, negedge reset_n) begin
        if(~reset_n) begin
            val <= 16'hA59D;
        end
        else if(seed_en) begin
            val <= seed ^ val;
        end
        else begin
            val <= {val[14:0], in};
        end
    end

endmodule : LFSR16
 
module WS2812B_Driver #(
    parameter CLK_MHZ   = 50,
 
    parameter T0H_CYCLES = 20,   // ~400 ns @ 50 MHz
    parameter T0L_CYCLES = 42,   // ~850 ns @ 50 MHz
    parameter T1H_CYCLES = 40,   // ~800 ns @ 50 MHz
    parameter T1L_CYCLES = 22,   // ~450 ns @ 50 MHz
    parameter RES_CYCLES = 2500, // >50 µs  @ 50 MHz
 
    parameter [23:0] COLOR_0 = 24'h00_00_00,   // 2'b00 -> off
    parameter [23:0] COLOR_1 = 24'h00_00_FF,   // 2'b01 -> blue, GRB: G=00 R=00 B=FF
    parameter [23:0] COLOR_2 = 24'h00_FF_00,   // 2'b10 -> red, GRB: G=00 R=FF B=00
    parameter [23:0] COLOR_3 = 24'hFF_FF_FF    // 2'b11 -> white, GRB: G=FF R=FF B=FF
)(
    input  logic        clock,
    input  logic        reset_n,
    input  logic [255:0] gridl_p,  
    input  logic [255:0] gridh_p,   
    output logic        ws_data
);
 
    logic [1:0] color [0:255];
 
    //Reconstruct the grid

    genvar i;
    generate
        for (i = 0; i < 256; i++) begin : 
            assign color[i] = {gridh_p[i], gridl_p[i]};
        end
    endgenerate
 
    //Color lookup

    function automatic [23:0] grb_of_color;
        input [1:0] c;
        case (c)
            2'b00:   grb_of_color = COLOR_0;
            2'b01:   grb_of_color = COLOR_1;
            2'b10:   grb_of_color = COLOR_2;
            default: grb_of_color = COLOR_3;
        endcase
    endfunction

    //FSM
 
    typedef enum logic [1:0] {RESET_ST, LOAD_ST, HIGH_ST, LOW_ST} cur_state, next_state;
 
    logic [11:0] timer;       
    logic [7:0] led_idx;     
    logic [4:0] bit_idx;        
    logic [23:0] shift_reg;      
    logic cur_bit;        
    logic [11:0] t_high, t_low;  
 
    always_ff @(posedge clock, negedge reset_n) begin
        if (~reset_n) begin
            timer     <= 12'd0;
            led_idx   <= 8'd0;
            bit_idx   <= 5'd23;
            shift_reg <= 24'd0;
            ws_data   <= 1'b0;
        end
        else begin
            case (state)
                RESET_ST: begin
                    ws_data <= 1'b0;
                    if (timer == RES_CYCLES - 1) begin
                        timer <= 12'd0;
                        led_idx <= 8'd0;
                        bit_idx <= 5'd23;
                        next_state <= LOAD_ST;
                    end
                    else begin
                        timer <= timer + 12'd1;
                        next_state <= RESET_ST;
                    end
                end
                LOAD_ST: begin
                    shift_reg <= grb_of_color(color[led_idx]);
                    bit_idx <= 5'd23;
                    next_state <= HIGH_ST;
                end
                HIGH_ST: begin
                    cur_bit <= shift_reg[bit_idx];
                    t_high <= shift_reg[bit_idx] ? T1H_CYCLES : T0H_CYCLES;
                    t_low <= shift_reg[bit_idx] ? T1L_CYCLES : T0L_CYCLES;
                    ws_data <= 1'b1;
 
                    if (timer == t_high - 1) begin
                        timer <= 12'd0;
                        next_state <= LOW_ST;
                    end
                    else begin
                        timer <= timer + 12'd1;
                        next_state <= HIGH_ST;
                    end
                end
                LOW_ST: begin
                    ws_data <= 1'b0;
 
                    if (timer == t_low - 1) begin
                        timer <= 12'd0;
 
                        if (bit_idx == 5'd0) begin
                            if (led_idx == 8'd255) begin
                                next_state <= RESET_ST;
                            end
                            else begin
                                led_idx <= led_idx + 8'd1;
                                next_state <= LOAD_ST;
                            end
                        end
                        else begin
                            bit_idx <= bit_idx - 5'd1;
                            next_state <= HIGH_ST;
                        end
                    end
                    else begin
                        timer <= timer + 12'd1;
                        next_state <= LOW_ST;
                    end
                end
            endcase
        end
    end

    always_ff @(posedge clock, negedge reset_n) begin
        if(~reset_n) begin
            cur_state <= RESET_ST;
        end
        else begin
            cur_state <= next_state;
        end
    end
 
endmodule : WS2812B_Driver