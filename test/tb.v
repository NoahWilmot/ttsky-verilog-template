`default_nettype none
`timescale 1ns / 1ps

/* Testbench for tt_um_example (StimulusGen)
   Driven by cocotb test.py
*/
module tb ();

    // Dump signals to FST
    initial begin
        $dumpfile("tb.fst");
        $dumpvars(0, tb);
        #1;
    end

    // Inputs and outputs
    reg        clk;
    reg        rst_n;
    reg        ena;
    reg  [7:0] ui_in;
    reg  [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

`ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
`endif

    tt_um_example user_project (
`ifdef GL_TEST
        .VPWR    (VPWR),
        .VGND    (VGND),
`endif
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    // Convenience aliases matching StimulusGen port names
    // Inputs
    wire gen         = ui_in[0];

    // Outputs
    wire wants_ctrl  = uio_out[0];
    wire wr_en       = uio_out[1];
    wire [1:0] wr_data = uio_out[3:2];
    wire [3:0] wr_row  = uo_out[3:0];
    wire [3:0] wr_col  = uo_out[7:4];

endmodule
