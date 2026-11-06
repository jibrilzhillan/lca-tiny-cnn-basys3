// relu_requant.v
// Signed round-half-up, ReLU and saturation; S1 comes from the model export.
`timescale 1ns/1ps
module relu_requant #(parameter integer S1=9)(
    input wire signed [23:0] acc,
    output reg [6:0] activation
);
    localparam integer ROUND_W=(S1>24)?S1+2:25;
    localparam signed [ROUND_W-1:0] ONE=1;
    localparam signed [ROUND_W-1:0] ROUNDING=(S1>0)?(ONE<<(S1-1)):0;
    wire signed [ROUND_W-1:0] extended={{(ROUND_W-24){acc[23]}},acc};
    wire signed [ROUND_W-1:0] rounded=extended+ROUNDING;
    wire signed [ROUND_W-1:0] shifted=rounded >>> ((S1>0)?S1:0);
    always @(*) begin
        if(shifted<=0) activation=0;
        else if(shifted>=127) activation=127;
        else activation=shifted[6:0];
    end
endmodule
