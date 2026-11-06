// maxpool_engine.v
// Test scaffolding only
// Opt-in synthetic transport model; exclude from production CNN sources.
`ifdef CNN_CORE_WIRING_TEST
`timescale 1ns/1ps
`include "cnn_params.vh"

module maxpool_engine (
    input wire clk, rst, start,
    input wire [`CNN_ACT_WIDTH-1:0] fm_rdata,
    output reg [`CNN_FMAP_ADDR_WIDTH-1:0] fm_raddr,
    output reg [`CNN_POOL_ADDR_WIDTH-1:0] pl_waddr,
    output reg [`CNN_ACT_WIDTH-1:0] pl_wdata,
    output reg pl_we, done, busy
);
    localparam IDLE=0, ISSUE=1, WAIT_READ=2, TAKE=3, STORE=4;
    reg [2:0] state_q;
    reg [1:0] tap_q;
    reg [`CNN_ACT_WIDTH-1:0] maximum_q;
    integer index_q;
    always @(posedge clk) begin
        if (rst) begin
            state_q<=IDLE; index_q<=0; tap_q<=0; maximum_q<=0;
            fm_raddr<=0; pl_waddr<=0; pl_wdata<=0;
            pl_we<=0; done<=0; busy<=0;
        end else begin
            pl_we<=0; done<=0;
            case (state_q)
                IDLE: if (start) begin
                    index_q<=0; tap_q<=0; busy<=1; state_q<=ISSUE;
                end
                // Deliberately use groups of four consecutive addresses
                // to cover the entire buffer; this is not 2D CNN pooling.
                ISSUE: begin
                    fm_raddr<=index_q*4+tap_q;
                    state_q<=WAIT_READ;
                end
                WAIT_READ: state_q<=TAKE;
                TAKE: begin
                    if (tap_q==0 || fm_rdata>maximum_q) maximum_q<=fm_rdata;
                    if (tap_q==3) state_q<=STORE;
                    else begin tap_q<=tap_q+1'b1; state_q<=ISSUE; end
                end
                STORE: begin
                    pl_waddr<=index_q; pl_wdata<=maximum_q; pl_we<=1;
                    if (index_q==`CNN_POOL_DEPTH-1) begin
                        done<=1; busy<=0; state_q<=IDLE;
                    end else begin
                        index_q<=index_q+1; tap_q<=0; state_q<=ISSUE;
                    end
                end
                default: state_q<=IDLE;
            endcase
        end
    end
endmodule
`endif
