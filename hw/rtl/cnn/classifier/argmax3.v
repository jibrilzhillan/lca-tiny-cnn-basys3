// argmax3.v
// Signed three-way argmax, lowest index wins ties; synchronous reset.
`timescale 1ns/1ps
module argmax3 (
    input wire clk, rst,
    input wire signed [31:0] logit0, logit1, logit2,
    output reg [1:0] class_id
);
    always @(posedge clk) begin
        if(rst) class_id<=0;
        else if(logit0>=logit1 && logit0>=logit2) class_id<=0;
        else if(logit1>=logit2) class_id<=1;
        else class_id<=2;
    end
endmodule
