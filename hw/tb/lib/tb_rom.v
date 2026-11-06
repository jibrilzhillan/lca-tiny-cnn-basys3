// tb_rom.v
// Verify ROM initialization, style parameters and one-cycle reads.
`timescale 1ns/1ps
`include "cnn_params.vh"
module tb_rom;
    reg clk;
    reg [`CNN_IMAGE_ADDR_WIDTH-1:0] image_addr;
    wire [7:0] image_data;
    reg [7:0] expected_images [0:`CNN_IMAGE_ROM_DEPTH-1];
    reg [3:0] addr;
    reg [1:0] bias_addr;
    wire [7:0] auto_data, block_data, lut_data;
    wire [31:0] bias_data;
    reg [7:0] expected [0:15];
    reg [31:0] expected_bias [0:2];
    reg [7:0] held;
    integer errors, i;

    `include "tb_utils.vh"

    rom #(.DATA_WIDTH(8),.ADDR_WIDTH(4),.DEPTH(16),.INIT_FILE("memory_test_u8.mem")) auto_rom
        (.clk(clk),.addr(addr),.data(auto_data));
    rom #(.DATA_WIDTH(8),.ADDR_WIDTH(4),.DEPTH(16),.INIT_FILE("memory_test_u8.mem"),.ROM_STYLE("block")) block_rom
        (.clk(clk),.addr(addr),.data(block_data));
    rom #(.DATA_WIDTH(8),.ADDR_WIDTH(4),.DEPTH(16),.INIT_FILE("memory_test_u8.mem"),.ROM_STYLE("distributed")) lut_rom
        (.clk(clk),.addr(addr),.data(lut_data));
    rom #(.DATA_WIDTH(32),.ADDR_WIDTH(2),.DEPTH(3),.INIT_FILE("memory_test_s32.mem"),.ROM_STYLE("distributed")) bias_rom
        (.clk(clk),.addr(bias_addr),.data(bias_data));

    rom #(.DATA_WIDTH(8),.ADDR_WIDTH(`CNN_IMAGE_ADDR_WIDTH),
          .DEPTH(`CNN_IMAGE_ROM_DEPTH),.INIT_FILE("core_test_images.mem"),.ROM_STYLE("block")) image_rom
        (.clk(clk),.addr(image_addr),.data(image_data));

    initial begin clk=0; forever #5 clk=~clk; end
    initial begin
        errors=0; addr=0; bias_addr=0; image_addr=0;
        $readmemh("core_test_images.mem",expected_images);
        $readmemh("memory_test_u8.mem",expected);
        $readmemh("memory_test_s32.mem",expected_bias);
        for(i=0;i<16;i=i+1) check((^expected[i]) !== 1'bx,"ROM fixture missing or incomplete");
        for(i=0;i<3;i=i+1) check((^expected_bias[i]) !== 1'bx,"bias fixture missing or incomplete");
        @(posedge clk); #1;
        for(i=0;i<16;i=i+1) begin
            @(negedge clk); held=auto_data; addr=i;
            #1;
            compare_word({24'd0,auto_data},{24'd0,held},i,"ROM holds before clock");
            compare_word({24'd0,block_data},{24'd0,held},i,"block ROM holds before clock");
            compare_word({24'd0,lut_data},{24'd0,held},i,"LUT ROM holds before clock");
            @(posedge clk); #1;
            compare_word({24'd0,auto_data},{24'd0,expected[i]},i,"auto ROM");
            compare_word({24'd0,block_data},{24'd0,expected[i]},i,"block ROM");
            compare_word({24'd0,lut_data},{24'd0,expected[i]},i,"distributed ROM");
        end
        for(i=0;i<3;i=i+1) begin
            @(negedge clk); bias_addr=i;
            @(posedge clk); #1;
            compare_word(bias_data,expected_bias[i],i,"32-bit bias ROM");
        end
        // Exercise all address bits and every image, including final word 32767.
        for(i=0;i<`CNN_IMAGE_ROM_DEPTH;i=i+1) begin
            @(negedge clk); held=image_data; image_addr=i;
            #1; compare_word({24'd0,image_data},{24'd0,held},i,"image ROM holds before clock");
            @(posedge clk); #1;
            check((^expected_images[i])!==1'bx,"image fixture incomplete");
            compare_word({24'd0,image_data},{24'd0,expected_images[i]},i,"full image ROM");
        end
        report_test;
        $finish;
    end
    initial begin
        #5000000;
        check(1'b0,"ROM test timeout"); report_test; $finish;
    end
endmodule
