// conv_engine.v
// Test scaffolding only
// Opt-in synthetic transport model; exclude from production CNN sources.
`ifdef CNN_CORE_WIRING_TEST
`timescale 1ns/1ps
`include "cnn_params.vh"

module conv_engine (
    input wire clk, rst, start,
    input wire [`CNN_IMAGE_ADDR_WIDTH-1:0] img_base,
    input wire [`CNN_PIXEL_WIDTH-1:0] img_data,
    output reg [`CNN_IMAGE_ADDR_WIDTH-1:0] img_addr,
    output reg [`CNN_FMAP_ADDR_WIDTH-1:0] fm_waddr,
    output reg [`CNN_ACT_WIDTH-1:0] fm_wdata,
    output reg fm_we, done, busy
);
    localparam IDLE=0, ISSUE=1, WAIT_READ=2, STORE=3;
    reg [1:0] state_q;
    reg [`CNN_IMAGE_ADDR_WIDTH-1:0] base_q;
    integer index_q;
    always @(posedge clk) begin
        if (rst) begin
            state_q<=IDLE; index_q<=0; base_q<=0;
            img_addr<=0; fm_waddr<=0; fm_wdata<=0;
            fm_we<=0; done<=0; busy<=0;
        end else begin
            fm_we<=0; done<=0;
            case (state_q)
                IDLE: if (start) begin
                    base_q<=img_base; index_q<=0; busy<=1; state_q<=ISSUE;
                end
                ISSUE: begin
                    img_addr<=base_q+(index_q % `CNN_IMG_PIXELS);
                    state_q<=WAIT_READ;
                end
                WAIT_READ: state_q<=STORE;
                STORE: begin
                    fm_waddr<=index_q;
                    fm_wdata<=(img_data ^ index_q[7:0]) & 8'h7f;
                    fm_we<=1;
                    if (index_q==`CNN_FMAP_DEPTH-1) begin
                        done<=1; busy<=0; state_q<=IDLE;
                    end else begin
                        index_q<=index_q+1; state_q<=ISSUE;
                    end
                end
                default: state_q<=IDLE;
            endcase
        end
    end
endmodule
`endif
