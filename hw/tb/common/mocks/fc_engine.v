// fc_engine.v
// Test scaffolding only
// Opt-in synthetic transport model; exclude from production CNN sources.
`ifdef CNN_CORE_WIRING_TEST
`timescale 1ns/1ps
`include "cnn_params.vh"

module fc_engine (
    input wire clk, rst, start,
    input wire [`CNN_ACT_WIDTH-1:0] pl_rdata,
    output reg [`CNN_POOL_ADDR_WIDTH-1:0] pl_raddr,
    output reg signed [`CNN_LOGIT_WIDTH-1:0] logit0, logit1, logit2,
    output reg done, busy
);
    localparam IDLE=0, ISSUE=1, WAIT_READ=2, TAKE=3;
    reg [1:0] state_q;
    reg signed [31:0] sum_q;
    wire signed [31:0] next_sum;
    integer index_q;
    assign next_sum = sum_q + $signed({24'd0, pl_rdata});
    always @(posedge clk) begin
        if (rst) begin
            state_q<=IDLE; index_q<=0; sum_q<=0; pl_raddr<=0;
            logit0<=0; logit1<=0; logit2<=0; done<=0; busy<=0;
        end else begin
            done<=0;
            case (state_q)
                IDLE: if (start) begin
                    index_q<=0; sum_q<=0; busy<=1; state_q<=ISSUE;
                end
                ISSUE: begin pl_raddr<=index_q; state_q<=WAIT_READ; end
                WAIT_READ: state_q<=TAKE;
                TAKE: begin
                    sum_q<=next_sum;
                    if (index_q==`CNN_POOL_DEPTH-1) begin
                        logit0<=next_sum-(`CNN_POOL_DEPTH*600/7);
                        logit1<=(`CNN_POOL_DEPTH*600/7)-next_sum;
                        logit2<=(`CNN_POOL_DEPTH/2);
                        done<=1; busy<=0; state_q<=IDLE;
                    end else begin index_q<=index_q+1; state_q<=ISSUE; end
                end
                default: state_q<=IDLE;
            endcase
        end
    end
endmodule
`endif
