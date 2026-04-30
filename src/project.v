/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire        wants_ctrl_w;
    wire        wr_en_w;
    wire [1:0]  wr_data_w;
    wire [3:0]  wr_row_w;
    wire [3:0]  wr_col_w;

    StimulusGen SG (
        .clock      (clk),
        .reset_n    (rst_n),
        .gen        (ui_in[0]),
        .wants_ctrl (wants_ctrl_w),
        .wr_en      (wr_en_w),
        .wr_data    (wr_data_w),
        .wr_row     (wr_row_w),
        .wr_col     (wr_col_w)
    );

    assign uio_out[0]   = wants_ctrl_w;
    assign uio_out[1]   = wr_en_w;
    assign uio_out[3:2] = wr_data_w;
    assign uio_out[7:4] = 4'b0000;

    assign uo_out[3:0]  = wr_row_w;
    assign uo_out[7:4]  = wr_col_w;

    assign uio_oe = 8'b0000_1111;

    wire _unused = &{ena, uio_in, ui_in[7:1], 1'b0};

endmodule
