`default_nettype none

module TileGrowth(
    input logic clock, reset_n,
    input logic up, down, left, right,
    input logic color_sel, place, start,
    output logic data,
    output logic [7:0] count
);

    //logic right;
    //assign right = 1'b0;
    //logic [7:0] count;

    logic [3:0] cursor_row, cursor_col;
    

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

    //write to the Grid
    always_ff @(posedge clock, negedge reset_n) begin
        if(~reset_n) begin
            for(int r = 0; r < 16; r++) begin
                gridl[r] <= 16'd0;
                gridh[r] <= 16'd0;
            end
        end
        /*else begin
            if(~game_start) begin
                for(int r = 0; r < 16; r++) begin
                    gridl[r] <= 16'hFFFF;
                    gridh[r] <= 16'hFFFF;
                end
            end
            else begin
                for(int r = 0; r < 16; r++) begin
                    gridl[r] <= 16'hFFFF;
                    gridh[r] <= 16'd0;
                end
            end
        end*/
        
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
        .cursor_row, .cursor_col,
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

    logic [255:0][23:0] frame;
 
    always_comb begin
        for (int i = 0; i < 256; i++) begin
            int row, col;
            row = i / 16;
            col = ((row % 2) == 1) ? (15 - (i % 16)) : (i % 16);
            if((cursor_row == row) && (cursor_col == col) && !game_start) begin
                frame[i] = 24'h15_00_00;
            end
            else begin
                case ({gridh[row][col], gridl[row][col]})
                    2'b00:   frame[i] = 24'h03_03_03; // white
                    2'b01:   frame[i] = 24'h00_00_15; // blue
                    2'b10:   frame[i] = 24'h00_15_00; // red
                    2'b11:   frame[i] = 24'h15_00_00; // green
                    default: frame[i] = 24'h00_00_00;
                endcase
            end 
        end
    end
    

    localparam int WAIT_T = 25 * 1_000_000 / 2; //half a second
    localparam int TIMER_WIDTH    = $clog2(WAIT_T + 1);
 
    logic [TIMER_WIDTH-1:0] led_timer;
    logic             led_start;
    logic             led_busy;
 
    always_ff @(posedge clock, negedge reset_n) begin
        if (~reset_n) begin
            led_timer <= TIMER_WIDTH'd0;
            led_start <= 1'b0;
        end else begin
            led_start <= 1'b0;
            if (led_timer == TIMER_WIDTH'(WAIT_T - 1)) begin
                led_timer <= '0;
                if (!led_busy) led_start <= 1'b1;
            end else begin
                led_timer <= led_timer + 1'b1;
            end
        end
    end
 

    ws2812b_driver u_drv (
        .clock,
        .reset_n,
        .pixel_matrix(frame),
        .start(led_start),
        .busy(led_busy),
        .dout(data)
    );

endmodule : TileGrowth


module PreStartFSM(
    input logic clock, reset_n,
    input logic up, down, left, right,
    input logic color_sel, place, start,
    output logic [3:0] cursor_row, cursor_col,
    //output logic [1:0] selected_color,
    output logic game_start,
    output logic wr_en,
    output logic [3:0] wr_row, wr_col,
    output logic [1:0] wr_data,
    output logic lfsr_seed_en,
    output logic [15:0] lfsr_seed
);

    //logic [3:0] cursor_row, cursor_col;
    logic [1:0] selected_color;

    /*
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
    */

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
                    //wr_en <= 1'b1;
                    //wr_row <= cursor_row;
                    //wr_col <= cursor_col;
                    //wr_data <= 2'b11;
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
    localparam STALL_MAX = 32'd500_0000; 
    //localparam STALL_MAX = 32'd10; // simulation

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


module ws2812b_driver #(parameter int CLK_MHZ = 25)(
    input  logic clock,
    input  logic reset_n,
    input  logic [255:0][23:0] pixel_matrix,  
    input  logic start,
    output logic busy,
    output logic dout
);

    localparam int T0H  = (CLK_MHZ * 400) / 1000;
    localparam int T0L  = (CLK_MHZ * 850) / 1000;
    localparam int T1H  = (CLK_MHZ * 800) / 1000;
    localparam int T1L  = (CLK_MHZ * 450) / 1000;
    localparam int TRES = (CLK_MHZ * 60000) / 1000;  
 
    localparam int CNT_WIDTH = $clog2(TRES + 1);
 
    enum logic [2:0] {IDLE, LOAD, SEND_HIGH, SEND_LOW, RESET_PULSE} cur_state, next_state;
 
    logic [CNT_WIDTH-1:0] cnt;
    logic [4:0] bit_idx;   
    logic [7:0] led_idx;  
    logic [23:0] shift_reg; 
    logic cur_bit;   
 
    assign busy = (cur_state != IDLE);

    always_comb begin
        case(cur_state)
            IDLE: begin
                next_state = start ? LOAD : IDLE;
            end
            LOAD: begin
                next_state = SEND_HIGH;
            end
            SEND_HIGH: begin
                next_state = (cnt == CNT_WIDTH'(cur_bit ? T1H-1 : T0H-1)) ? SEND_LOW : SEND_HIGH;    
            end
            SEND_LOW: begin
                if (cnt == CNT_WIDTH'(cur_bit ? T1L-1 : T0L-1)) begin
                    if (bit_idx != 5'd0) next_state  <= SEND_HIGH;
                    else begin
                        if (led_idx == 8'd255) next_state <= RESET_PULSE;
                        else next_state <= LOAD;
                    end     
                end
                else next_state <= SEND_LOW;
            end
            RESET_PULSE: begin
                next_state = (cnt == CNT_WIDTH'(TRES - 1)) ? IDLE : RESET_PULSE;
            end
            default: next_state = IDLE;
        endcase
    end
 
    always_ff @(posedge clock, negedge reset_n) begin
        if (~reset_n) begin
            dout      <= 1'b0;
            cnt       <= '0;
            bit_idx   <= 5'd23;
            led_idx   <= 8'd0;
            shift_reg <= 24'd0;
            cur_bit   <= 1'b0;
        end else begin
            case (cur_state)
                IDLE: begin
                    dout <= 1'b0;
                    if (start) begin
                        led_idx <= 8'd0;
                        bit_idx <= 5'd23;
                        cnt     <= '0;
                    end
                end
                LOAD: begin
                    shift_reg <= pixel_matrix[led_idx];
                    cur_bit   <= pixel_matrix[led_idx][23];  
                    cnt       <= '0;
                end
                SEND_HIGH: begin
                    dout <= 1'b1;
                    if (cnt == CNT_WIDTH'(cur_bit ? T1H-1 : T0H-1)) begin
                        cnt   <= '0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
                SEND_LOW: begin
                    dout <= 1'b0;
                    if (cnt == CNT_WIDTH'(cur_bit ? T1L-1 : T0L-1)) begin
                        cnt <= '0;
                        if (bit_idx != 5'd0) begin
                            bit_idx <= bit_idx - 1'b1;
                            cur_bit <= shift_reg[bit_idx - 1];
                        end else begin
                            bit_idx <= 5'd23;
                            if (led_idx != 8'd255) begin
                                led_idx <= led_idx + 1'b1;
                            end
                        end
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
                RESET_PULSE: begin
                    dout <= 1'b0;
                    if (cnt == CNT_WIDTH'(TRES - 1)) begin
                        cnt   <= '0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
                default: ;
            endcase
        end
    end

    always_ff @(posedge clock, negedge reset_n) begin
        if(~reset_n) begin 
            cur_state <= IDLE;
        end
        else begin
            cur_state <= next_state;
        end
    end

endmodule : ws2812b_driver
 