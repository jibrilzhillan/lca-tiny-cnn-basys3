// cnn_core.v
// Integrate controller, generic memory instances and the conv and classifier engines.
`timescale 1ns/1ps
`include "cnn_params.vh"

// Accelerator integration, independent of Basys3 buttons and displays.
// Requires conv_engine, maxpool_engine, fc_engine and argmax3.
// Weight/bias ROMs sit inside the conv and FC engines; this module
// supplies image ROM, inter-stage buffers, sequencing and result capture.
module cnn_core #(
    parameter IMAGE_FILE = "test_images.mem"
) (
    input  wire                              clk,
    input  wire                              rst,
    input  wire                              start,
    input  wire [`CNN_IMG_SEL_WIDTH-1:0]      img_sel,
    output wire                              done,
    output wire                              busy,
    output reg  [`CNN_CLASS_WIDTH-1:0]        class_id,
    output wire signed [`CNN_LOGIT_WIDTH-1:0] logit0,
    output wire signed [`CNN_LOGIT_WIDTH-1:0] logit1,
    output wire signed [`CNN_LOGIT_WIDTH-1:0] logit2,
    output wire [`CNN_CYCLE_WIDTH-1:0]        cycle_count
);

    wire conv_start, pool_start, fc_start, argmax_start;
    wire conv_done, pool_done, fc_done;
    wire conv_busy, pool_busy, fc_busy;
    wire [`CNN_IMG_SEL_WIDTH-1:0] img_sel_q;
    wire [`CNN_IMAGE_ADDR_WIDTH-1:0] img_base, img_addr;
    wire [`CNN_PIXEL_WIDTH-1:0] img_data;
    wire [`CNN_FMAP_ADDR_WIDTH-1:0] fm_waddr, fm_raddr;
    wire [`CNN_ACT_WIDTH-1:0] fm_wdata, fm_rdata;
    wire fm_we;
    wire [`CNN_POOL_ADDR_WIDTH-1:0] pl_waddr, pl_raddr;
    wire [`CNN_ACT_WIDTH-1:0] pl_wdata, pl_rdata;
    wire pl_we;
    wire [`CNN_CLASS_WIDTH-1:0] argmax_class;

    // 2048 words/image: at 64x32 this is img_sel << 11.
    // The live switches never feed the engine's image base directly.
    assign img_base = {img_sel_q, {`CNN_IMAGE_OFFSET_WIDTH{1'b0}}};

    cnn_ctrl u_ctrl (
        .clk(clk), .rst(rst), .start(start), .img_sel(img_sel),
        .conv_done(conv_done), .pool_done(pool_done), .fc_done(fc_done),
        .conv_start(conv_start), .pool_start(pool_start),
        .fc_start(fc_start), .argmax_start(argmax_start),
        .busy(busy), .done(done), .img_sel_q(img_sel_q),
        .cycle_count(cycle_count)
    );

    rom #(
        .DATA_WIDTH(`CNN_PIXEL_WIDTH),
        .ADDR_WIDTH(`CNN_IMAGE_ADDR_WIDTH),
        .DEPTH(`CNN_IMAGE_ROM_DEPTH),
        .INIT_FILE(IMAGE_FILE),
        .ROM_STYLE("block")
    ) image_rom (
        .clk(clk), .addr(img_addr), .data(img_data)
    );

    conv_engine u_conv (
        .clk(clk), .rst(rst), .start(conv_start),
        .done(conv_done), .busy(conv_busy),
        .img_base(img_base), .img_addr(img_addr), .img_data(img_data),
        .fm_waddr(fm_waddr), .fm_wdata(fm_wdata), .fm_we(fm_we)
    );

    // Suppress pending writes on reset. Do not gate by engine busy:
    // an engine may lower busy alongside its final write-enable pulse.
    ram #(
        .DATA_WIDTH(`CNN_ACT_WIDTH),
        .ADDR_WIDTH(`CNN_FMAP_ADDR_WIDTH),
        .DEPTH(`CNN_FMAP_DEPTH),
        .RAM_STYLE("block")
    ) fmap_ram (
        .clk(clk), .we(fm_we && !rst),
        .waddr(fm_waddr), .wdata(fm_wdata),
        .raddr(fm_raddr), .rdata(fm_rdata)
    );

    maxpool_engine u_pool (
        .clk(clk), .rst(rst), .start(pool_start),
        .done(pool_done), .busy(pool_busy),
        .fm_raddr(fm_raddr), .fm_rdata(fm_rdata),
        .pl_waddr(pl_waddr), .pl_wdata(pl_wdata), .pl_we(pl_we)
    );

    ram #(
        .DATA_WIDTH(`CNN_ACT_WIDTH),
        .ADDR_WIDTH(`CNN_POOL_ADDR_WIDTH),
        .DEPTH(`CNN_POOL_DEPTH),
        .RAM_STYLE("block")
    ) pool_ram (
        .clk(clk), .we(pl_we && !rst),
        .waddr(pl_waddr), .wdata(pl_wdata),
        .raddr(pl_raddr), .rdata(pl_rdata)
    );

    fc_engine u_fc (
        .clk(clk), .rst(rst), .start(fc_start),
        .done(fc_done), .busy(fc_busy),
        .pl_raddr(pl_raddr), .pl_rdata(pl_rdata),
        .logit0(logit0), .logit1(logit1), .logit2(logit2)
    );

    // Contract: signed comparison and one registered output, lowest
    // index wins ties. No start/done interface is needed for this stage.
    argmax3 u_argmax (
        .clk(clk), .rst(rst),
        .logit0(logit0), .logit1(logit1), .logit2(logit2),
        .class_id(argmax_class)
    );

    // FC logits are registered before fc_done reaches the controller.
    // The ARGMAX cycle lets u_argmax register the new class, then this
    // register captures it on the same edge that the controller raises
    // DONE. The displayed class holds until the next completed run.
    always @(posedge clk) begin
        if (rst) begin
            class_id <= `CNN_CLASS_LEFT;
        end else if (argmax_start) begin
            class_id <= argmax_class;
        end
    end
endmodule
