`default_nettype none

module StimulusGen (
    input logic clock,
    input logic reset_n,
    input logic gen,
    output logic wants_ctrl,
    output logic wr_en,
    output logic [3:0] wr_row,
    output logic [3:0] wr_col,
    output logic [1:0] wr_data
);

      ////////////////////////
     // Debounce gen press //
    ////////////////////////
    
    localparam int CLK_MHZ = 25;
    localparam int STABLE_MS = 20; //time button must be stable for
    localparam int STABLE_CNT = CLK_MHZ * 1000 * STABLE_MS;
    localparam int DEB_WIDTH = $clog2(STABLE_CNT + 1);

    logic [1:0] gen_sync;
    logic [DEB_WIDTH:0] deb_cnt;
    logic gen_stable, gen_pulse;

    always_ff @(posedge clock, negedge reset_n) begin
        if (~reset_n) begin 
            gen_sync <= 2'b00;
        end
        else begin
            gen_sync <= {gen_sync[0], gen};
        end
    end

    always_ff @(posedge clock, negedge reset_n) begin
        if (~reset_n) begin
            deb_cnt    <= '0;
            gen_stable <= 1'b0;
            gen_pulse  <= 1'b0;
        end 
        else begin
            gen_pulse <= 1'b0;
            if (gen_sync[1] != gen_stable) begin
                if (deb_cnt == DEB_WIDTH'(STABLE_CNT - 1)) begin
                    deb_cnt    <= '0;
                    gen_stable <= gen_sync[1];
                    if (gen_sync[1]) gen_pulse <= 1'b1;
                end else begin
                    deb_cnt <= deb_cnt + 1'b1;
                end
            end else begin
                deb_cnt <= '0;
            end
        end
    end

      /////////////////////////////////////////////
     // Free Counter to randomize the LFSR seed //
    /////////////////////////////////////////////

    logic [15:0] free_cnt;

    always_ff @(posedge clock, negedge reset_n) begin
        if (~reset_n) begin 
            free_cnt <= 16'd0;
        end
        else begin         
            free_cnt <= free_cnt + 1'b1;
        end
    end

      ////////////////////////////////////////////
     // LFSR to randomize tile positions/color //
    ////////////////////////////////////////////

    localparam logic [15:0] FIXED_SEED = 16'hD59B;
    logic [15:0] seed;

    assign seed = FIXED_SEED ^ free_cnt;

    logic [15:0] lfsr_val;
    logic lfsr_in;

    assign lfsr_in = lfsr_val[15] ^ lfsr_val[13] ^ lfsr_val[12] ^ lfsr_val[10];

    always_ff @(posedge clock, negedge reset_n) begin
        if (~reset_n) begin
            lfsr_val <= FIXED_SEED;
        end
        else if (gen_pulse) begin
            lfsr_val <= seed;
        end
        else begin
            lfsr_val <= {lfsr_val[14:0], lfsr_in};
        end
    end

      ////////////////////
     //  Places tiles  //
    ////////////////////

    enum logic [1:0] {IDLE,SWEEP,DONE} cur_state, next_state;

    logic [3:0] row, col;
    logic [1:0] cur_color;

    // Next state logic
    always_comb begin
        case(cur_state)
            IDLE: begin
                if(gen_pulse) next_state = SWEEP;
                else next_state = IDLE;
            end
            SWEEP: begin
                if((col == 4'd15) && (row == 4'd15)) next_state = DONE;
                else next_state = SWEEP;
            end
            DONE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // FSM Output / Datapath
    always_ff @(posedge clock, negedge reset_n) begin
        if (~reset_n) begin
            row      <= 4'd0;
            col      <= 4'd0;
            cur_color  <= 2'd1;
            wants_ctrl <= 1'b0;
            wr_en      <= 1'b0;
            wr_row     <= 4'd0;
            wr_col     <= 4'd0;
            wr_data    <= 2'd0;
        end else begin
            wr_en <= 1'b0;
            case (cur_state)
                IDLE: begin
                    wants_ctrl <= 1'b0;
                    if (gen_pulse) begin
                        row      <= 4'd0;
                        col      <= 4'd0;
                        cur_color  <= 2'd1; 
                        wants_ctrl <= 1'b1;
                    end
                end
                SWEEP: begin
                    wants_ctrl <= 1'b1;
                    // 50/50 color toggle
                    if (lfsr_val[0])
                        cur_color <= (cur_color == 2'd1) ? 2'd2 : 2'd1;
                    // 1/16 place
                    if (lfsr_val[3:0] == 4'hF) begin
                        wr_en   <= 1'b1;
                        wr_row  <= row;
                        wr_col  <= col;
                        wr_data <= cur_color;
                    end
                    // Advance position
                    if (col == 4'd15) begin
                        col <= 4'd0;
                        if (row != 4'd15)
                            row <= row + 1'b1;
                    end else begin
                        col <= col + 1'b1;
                    end
                end
                DONE: begin
                    wants_ctrl <= 1'b0;
                end
                default: ;
            endcase
        end
    end

    //State register
    always_ff @(posedge clock, negedge reset_n) begin
        if(~reset_n) begin
            cur_state <= IDLE;
        end
        else begin
            cur_state <= next_state;
        end
    end

endmodule : StimulusGen