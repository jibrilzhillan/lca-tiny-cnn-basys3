// mac.v
// Signed multiply-accumulate for conv_engine (u8 pixel x s8 weight, 24-bit accumulator), mapped to one DSP48E1.
`timescale 1ns/1ps

module mac (
    input  wire clk,
    input  wire rst,

    input  wire acc_clear,
    input  wire acc_load,
    input  wire acc_enable,

    input  wire [7:0] pixel,
    input  wire signed [7:0] weight,

    input  wire signed [23:0] acc_load_data,
    output reg  signed [23:0] acc
);

    // Convert unsigned pixel into positive signed 9-bit value
    wire signed [8:0] pixel_signed;

    assign pixel_signed = {1'b0, pixel};

    // Multiply and accumulate datapath
    (* use_dsp = "yes" *)
    wire signed [23:0] mac_result;

    assign mac_result =
        acc + (pixel_signed * weight);

    // Sequential accumulator
    always @(posedge clk) begin
        if (rst) begin
            acc <= 24'sd0;
        end
        else if (acc_clear) begin
            acc <= 24'sd0;
        end
        else if (acc_load) begin
            acc <= acc_load_data;
        end
        else if (acc_enable) begin
            acc <= mac_result;
        end
    end

endmodule