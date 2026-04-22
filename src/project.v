/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  TG TileGrowth(.clock(clk), .reset_n(rst_n), .up(ui_in[0]), .down(ui_in[1]), .left(ui_in[2]), .right(ui_in[3]), .color_sel(ui_in[4]), .place(ui_in[5]), .start(ui_in[6]), .data(uo_out[0]), .count(uio_out);
  //RangeFinder #(8) RF(.data_in(ui_in), .clock(clk),. reset(reset), .go(uio_in[0]), .finish(uio_in[1]), .range(uo_out), .error(uio_out[2]));

  // All output pins must be assigned. If not used, assign to 0.
  //assign uo_out  = ui_in + uio_in;  // Example: ou_out is the sum of ui_in and uio_in
  assign uio_oe  = 8'b1111_1111;
  assign uo_out[7:1] = 7'b000_0000;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, uio_in,  ui_in[7], 1'b0};

endmodule
