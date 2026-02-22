
module RangeFinder
   #(parameter WIDTH=16)
    (input  logic [WIDTH-1:0] data_in,
     input  logic             clock, reset,
     input  logic             go, finish,
     output logic [WIDTH-1:0] range,
     output logic             error);

// Put your code here
logic new_min, new_max, min_en, max_en;
logic [WIDTH-1:0] min_reg_out, max_reg_out;
logic init;

fsm control(.*);

assign min_en = init | new_min;
assign max_en = init | new_max;

MagComp #(WIDTH) min_comp(data_in, min_reg_out,,,new_min);
MagComp #(WIDTH) max_comp(data_in, max_reg_out,new_max,,);

Register #(WIDTH) min_reg(data_in, min_en, , clock, min_reg_out);
Register #(WIDTH) max_reg(data_in, max_en, , clock, max_reg_out);

assign range = max_reg_out - min_reg_out;



endmodule: RangeFinder

module fsm
(input logic clock, reset,
 input logic go, finish,
 output logic error, init);

 enum logic [1:0] {IDLE = 2'b00, ACTIVE = 2'b01, ERROR = 2'b10, ACTIVE2 = 2'b11} cur_state, n_state;

 always_comb begin
   init = 1'b0;
   case(cur_state)
   IDLE: begin
      n_state = IDLE;
      if(go) begin
      n_state = ACTIVE;
      init = 1'b1;
      end
      if(finish) n_state = ERROR;
      error = 1'b0;
   end
   ACTIVE: begin
      n_state = ACTIVE;
      if(finish) n_state = IDLE;
      if(go & finish) n_state = ERROR;
      if(~go) n_state = ACTIVE2;
      error = 1'b0;
   end
   ACTIVE2: begin
      n_state = ACTIVE2;
      if(go) n_state = ERROR;
      if(finish) n_state = IDLE;
   end
   ERROR: begin
      n_state = ERROR;
      if(go) n_state = ACTIVE;
      error = 1'b1;
   end
   endcase
 end

 always_ff @(posedge clock, posedge reset) begin
   if(reset)
      cur_state <= IDLE;
   else
      cur_state <= n_state;
 end

endmodule: fsm

module MagComp 
 #(parameter w = 8)
 (input  logic [w-1:0] A, B,
  output logic AgtB, AeqB, AltB);

  assign AeqB = (A == B);
  assign AgtB = (A > B);
  assign AltB = (A < B);

endmodule: MagComp

module Register 
 #(parameter w = 8)
 (input logic [w-1:0] D,
  input logic en, cl, clock,
  output logic [w-1:0] Q);

  always_ff @ (posedge clock)begin
    if(en)
        Q <= D;
    else if(cl)
        Q <= 0;
  end

endmodule: Register