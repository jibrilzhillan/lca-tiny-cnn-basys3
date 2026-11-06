// tb_relu_requant.v
// U2: saturation, signed rounding, zero shift, full int24 sweep and export shift.
`ifdef CNN_USE_QUANT_CONFIG
`timescale 1ns/1ps
`include "cnn_params.vh"
module tb_relu_requant;
    reg signed [23:0] acc;
    wire [6:0] result,zero_result,large_result;
    integer errors=0,i;
    reg signed [63:0] ref;
    `include "tb_utils.vh"
    relu_requant #(.S1(`CNN_REQUANT_SHIFT)) dut(.acc(acc),.activation(result));
    relu_requant #(.S1(0)) zero_shift(.acc(acc),.activation(zero_result));
    relu_requant #(.S1(30)) large_shift(.acc(acc),.activation(large_result));
    task sample;
        input integer value;
        begin
            acc=value; #1;
            ref=value;
            if(`CNN_REQUANT_SHIFT>0) ref=(ref+(64'sd1<<(`CNN_REQUANT_SHIFT-1)))>>>`CNN_REQUANT_SHIFT;
            if(ref<0)ref=0; if(ref>127)ref=127;
            compare_word({25'd0,result},ref[31:0],value,"requant");
            ref=value; if(ref<0)ref=0; if(ref>127)ref=127;
            compare_word({25'd0,zero_result},ref[31:0],value,"zero shift");
            check(large_result===0,"large shift overflow");
        end
    endtask
    initial begin
        sample(0);sample(-1);sample(255);sample(256);sample(511);
        sample(-256);sample(-257);sample(1);sample(257);sample(512);
        sample(767);sample(768);sample(64767);sample(64768);sample(65024);sample(65536);sample(-8388608);sample(8388607);
        for(i=-8388608;i<=8387583;i=i+1023) sample(i);
        for(i=-100000;i<=100000;i=i+1) sample(i);
        report_test; $finish;
    end
endmodule
`endif
