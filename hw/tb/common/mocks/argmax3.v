// argmax3.v
// Test scaffolding only
// Opt-in synthetic transport model; exclude from production CNN sources.
`ifdef CNN_CORE_WIRING_TEST
`timescale 1ns/1ps
`include "cnn_params.vh"

module argmax3 (
    input wire clk, rst,
    input wire signed [`CNN_LOGIT_WIDTH-1:0] logit0, logit1, logit2,
    output reg [`CNN_CLASS_WIDTH-1:0] class_id
);
    always @(posedge clk) begin
        if (rst) class_id<=`CNN_CLASS_LEFT;
        else if (logit0>=logit1 && logit0>=logit2) class_id<=`CNN_CLASS_LEFT;
        else if (logit1>=logit2) class_id<=`CNN_CLASS_STRAIGHT;
        else class_id<=`CNN_CLASS_RIGHT;
    end
endmodule
`endif
