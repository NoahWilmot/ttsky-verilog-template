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

    // -------------------------------------------------------------------------
    // Debounce gen
    // -------------------------------------------------------------------------
    localparam int CLK_MHZ = 25;
    localparam int STABLE_MS = 20;
    localparam int STABLE_CNT = CLK_MHZ * 1000 * STABLE_MS;
    localparam int DEB_W = $clog2(STABLE_CNT + 1);

    logic [1:0] gen_sync;
    logic [DEB_W:0] deb_cnt;
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
                if (deb_cnt == DEB_W'(STABLE_CNT - 1)) begin
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

    // -------------------------------------------------------------------------
    // Free-running counter — used to randomise the LFSR seed on each gen press
    // -------------------------------------------------------------------------
    logic [15:0] free_cnt;

    always_ff @(posedge clock, negedge reset_n) begin
        if (~reset_n) begin 
            free_cnt <= 16'd0;
        end
        else begin         
            free_cnt <= free_cnt + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Internal LFSR — shifts every clock, seeds from counter XOR fixed on gen
    // -------------------------------------------------------------------------
    localparam logic [15:0] FIXED_SEED = 16'hA59D;

    logic [15:0] lfsr_val;
    logic lfsr_in;

    assign lfsr_in = lfsr_val[15] ^ lfsr_val[13] ^ lfsr_val[12] ^ lfsr_val[10];

    always_ff @(posedge clock, negedge reset_n) begin
        if (~reset_n) begin
            lfsr_val <= FIXED_SEED;
        end
        else if (gen_pulse) begin
            lfsr_val <= FIXED_SEED ^ free_cnt;
        end
        else begin
            lfsr_val <= {lfsr_val[14:0], lfsr_in};
        end
    end

    // -------------------------------------------------------------------------
    // Sweep FSM
    // -------------------------------------------------------------------------
    enum logic [1:0] {IDLE,SWEEP,DONE} cur_state, next_state;

    logic [3:0] s_row, s_col;
    logic [1:0] cur_color;

    always_comb begin
        case(cur_state)
            IDLE: begin
                next_state = gen_pulse ? SWEEP : IDLE;
            end
            SWEEP: begin
                next_state = ((s_col == 4'd15) && (s_row == 4'd15)) ? DONE ? SWEEP;
            end
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge clock, negedge reset_n) begin
        if (~reset_n) begin
            s_row      <= 4'd0;
            s_col      <= 4'd0;
            cur_color  <= 2'd1;
            wants_ctrl <= 1'b0;
            wr_en      <= 1'b0;
            wr_row     <= 4'd0;
            wr_col     <= 4'd0;
            wr_data    <= 2'd0;
        end else begin
            wr_en <= 1'b0;
            case (state)
                IDLE: begin
                    wants_ctrl <= 1'b0;
                    if (gen_pulse) begin
                        s_row      <= 4'd0;
                        s_col      <= 4'd0;
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
                        wr_row  <= s_row;
                        wr_col  <= s_col;
                        wr_data <= cur_color;
                    end
                    // Advance position
                    if (s_col == 4'd15) begin
                        s_col <= 4'd0;
                        if (s_row != 4'd15)
                            s_row <= s_row + 1'b1;
                    end else begin
                        s_col <= s_col + 1'b1;
                    end
                end
                DONE: begin
                    wants_ctrl <= 1'b0;
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

endmodule : StimulusGen