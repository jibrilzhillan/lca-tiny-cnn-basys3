// fc_engine.v
// Sequential unsigned-activation/signed-weight FC with internal ROMs.
`timescale 1ns/1ps
`include "cnn_params.vh"
module fc_engine #(
    parameter WEIGHT_FILE="fc_weight.mem",
    parameter BIAS_FILE="fc_bias.mem"
)(
    input wire clk, rst, start,
    output reg busy, done,
    output wire [`CNN_POOL_ADDR_WIDTH-1:0] pl_raddr,
    input wire [7:0] pl_rdata,
    output reg signed [31:0] logit0, logit1, logit2
);
    localparam IDLE=0, WAIT_READ=1, MAC=2, STORE=3, FINISH=4;
    reg [2:0] state;
    reg [1:0] class_idx;
    reg [`CNN_POOL_ADDR_WIDTH-1:0] data_idx;
    reg signed [31:0] accum;
    wire [`CNN_FC_W_ADDR_WIDTH-1:0] weight_addr=class_idx*`CNN_FC_INPUTS+data_idx;
    wire signed [7:0] weight_data;
    wire signed [31:0] bias_data;
    // Explicit zero extension preserves the unsigned activation value.
    wire signed [8:0] activation=$signed({1'b0,pl_rdata});

    (* use_dsp = "yes" *)
    wire signed [16:0] product=activation*weight_data;
    assign pl_raddr=data_idx;
    rom #(.DATA_WIDTH(8),.ADDR_WIDTH(`CNN_FC_W_ADDR_WIDTH),.DEPTH(`CNN_FC_W_DEPTH),
          .INIT_FILE(WEIGHT_FILE),.ROM_STYLE("block")) fc_w_rom (
          .clk(clk),.addr(weight_addr),.data(weight_data));
    rom #(.DATA_WIDTH(32),.ADDR_WIDTH(`CNN_FC_B_ADDR_WIDTH),.DEPTH(`CNN_FC_B_DEPTH),
          .INIT_FILE(BIAS_FILE),.ROM_STYLE("distributed")) fc_b_rom (
          .clk(clk),.addr(class_idx),.data(bias_data));
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE; busy<=0; done<=0; class_idx<=0;
            data_idx<=0; accum<=0; logit0<=0; logit1<=0; logit2<=0;
        end else begin
            done<=0;
            case(state)
                IDLE: if(start) begin
                    busy<=1; class_idx<=0; data_idx<=0; accum<=0;
                    state<=WAIT_READ;
                end
                WAIT_READ: state<=MAC;
                MAC: begin
                    accum<=accum+{{15{product[16]}},product};
                    if(data_idx==`CNN_FC_INPUTS-1) state<=STORE;
                    else begin data_idx<=data_idx+1'b1; state<=WAIT_READ; end
                end
                // The last MAC has committed; add the class bias once.
                STORE: begin
                    case(class_idx)
                        0: logit0<=accum+bias_data;
                        1: logit1<=accum+bias_data;
                        2: logit2<=accum+bias_data;
                    endcase
                    if(class_idx==2) state<=FINISH;
                    else begin
                        class_idx<=class_idx+1'b1; data_idx<=0;
                        accum<=0; state<=WAIT_READ;
                    end
                end
                FINISH: begin busy<=0; done<=1; state<=IDLE; end
                default: begin state<=IDLE; busy<=0; end
            endcase
        end
    end
endmodule
