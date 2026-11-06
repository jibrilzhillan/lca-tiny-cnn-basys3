// maxpool_engine.v
// 2x2 max over channel-major valid Conv maps, five clocks per output.
`timescale 1ns/1ps
`include "cnn_params.vh"
module maxpool_engine(
    input wire clk,rst,start,
    output reg busy,done,
    output wire [`CNN_FMAP_ADDR_WIDTH-1:0] fm_raddr,
    input wire [7:0] fm_rdata,
    output reg [`CNN_POOL_ADDR_WIDTH-1:0] pl_waddr,
    output reg [7:0] pl_wdata,
    output reg pl_we
);
    localparam IDLE=0,READ0=1,READ1=2,READ2=3,READ3=4,OUTPUT=5,FINISH=6;
    reg [2:0] state;
    reg [1:0] channel,tap;
    reg [$clog2(`CNN_POOL_OUT_HEIGHT)-1:0] y;
    reg [$clog2(`CNN_POOL_OUT_WIDTH)-1:0] x;
    reg [7:0] maximum;
    wire [`CNN_FMAP_ADDR_WIDTH-1:0] base=channel*`CNN_FMAP_PLANE_SIZE+y*2*`CNN_CONV_OUT_WIDTH+x*2;
    assign fm_raddr=base+(tap[1]?`CNN_CONV_OUT_WIDTH:0)+tap[0];
    wire [7:0] next_max=(fm_rdata>maximum)?fm_rdata:maximum;
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;busy<=0;done<=0;pl_we<=0;channel<=0;
            y<=0;x<=0;tap<=0;maximum<=0;pl_waddr<=0;pl_wdata<=0;
        end else begin
            done<=0;pl_we<=0;
            case(state)
                IDLE: if(start) begin
                    busy<=1;channel<=0;y<=0;x<=0;tap<=0;state<=READ0;
                end
                READ0: begin tap<=1;state<=READ1;end
                READ1: begin maximum<=fm_rdata;tap<=2;state<=READ2;end
                READ2: begin maximum<=next_max;tap<=3;state<=READ3;end
                READ3: begin maximum<=next_max;state<=OUTPUT;end
                OUTPUT: begin
                    pl_waddr<=channel*`CNN_POOL_PLANE_SIZE+y*`CNN_POOL_OUT_WIDTH+x;
                    pl_wdata<=next_max;pl_we<=1;tap<=0;
                    if(x==`CNN_POOL_OUT_WIDTH-1 && y==`CNN_POOL_OUT_HEIGHT-1 && channel==`CNN_CONV_FILTERS-1)
                        state<=FINISH;
                    else begin
                        if(x==`CNN_POOL_OUT_WIDTH-1) begin
                            x<=0;
                            if(y==`CNN_POOL_OUT_HEIGHT-1) begin y<=0;channel<=channel+1'b1;end
                            else y<=y+1'b1;
                        end else x<=x+1'b1;
                        state<=READ0;
                    end
                end
                FINISH: begin busy<=0;done<=1;state<=IDLE;end
                default: begin busy<=0;state<=IDLE;end
            endcase
        end
    end
endmodule
