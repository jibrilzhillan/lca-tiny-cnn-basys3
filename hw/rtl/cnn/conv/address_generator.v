// address_generator.v
// Row-major 3x3 pixel addresses from the shared input width.
`timescale 1ns/1ps
`include "cnn_params.vh"
module address_generator (
    input wire [`CNN_IMAGE_ADDR_WIDTH-1:0] img_base,
    input wire [$clog2(`CNN_CONV_OUT_HEIGHT)-1:0] oy,
    input wire [$clog2(`CNN_CONV_OUT_WIDTH)-1:0] ox,
    input wire [3:0] k,
    output wire [`CNN_IMAGE_ADDR_WIDTH-1:0] img_addr
);
    assign img_addr = img_base + (oy + k/3)*`CNN_IMG_WIDTH + ox + k%3;
endmodule
