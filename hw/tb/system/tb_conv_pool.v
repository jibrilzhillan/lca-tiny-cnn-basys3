// tb_conv_pool.v
// I2: real Conv-Pool outputs checked for all images through the core.
`timescale 1ns/1ps
`include "cnn_params.vh"
module tb_conv_pool;
    reg clk=0,rst=1,start=0;
    always #5 clk=~clk;
    reg [3:0] image_sel=0;
    wire busy,done;
    wire [1:0] cls;
    wire signed [31:0] l0,l1,l2;
    wire [`CNN_CYCLE_WIDTH-1:0] count;
    reg [7:0] conv_expected[0:`CNN_NUM_IMAGES*`CNN_FMAP_DEPTH-1];
    reg [7:0] pool_expected[0:`CNN_NUM_IMAGES*`CNN_POOL_DEPTH-1];
    reg [31:0] logits_expected[0:`CNN_NUM_IMAGES*3-1];
    reg [1:0] class_expected[0:`CNN_NUM_IMAGES-1];
    integer errors=0,n,i,cycles,baseline=-1,stage;
    `include "tb_utils.vh"
    cnn_core dut(.clk(clk),.rst(rst),.start(start),.img_sel(image_sel),.busy(busy),.done(done),
        .class_id(cls),.logit0(l0),.logit1(l1),.logit2(l2),.cycle_count(count));
    task run_image;
        input integer k;
        begin
            @(negedge clk);image_sel=k;start=1;
            @(negedge clk);start=0;image_sel=15-k;cycles=0;
            while(!done && cycles<`CNN_TARGET_CYCLES+1) begin @(negedge clk);cycles=cycles+1;end
            check(done && !busy,"Core timeout/status mismatch");
            check(count==cycles && count<=`CNN_TARGET_CYCLES,"I4 cycle count/target mismatch");
            if(baseline<0)baseline=count;
            check(count==baseline,"I4 latency varies between images");
            for(i=0;i<`CNN_FMAP_DEPTH;i=i+1) compare_word(dut.fmap_ram.mem[i],conv_expected[k*`CNN_FMAP_DEPTH+i],i,"Core Conv");
            for(i=0;i<`CNN_POOL_DEPTH;i=i+1) compare_word(dut.pool_ram.mem[i],pool_expected[k*`CNN_POOL_DEPTH+i],i,"Core Pool");
            compare_word(l0,logits_expected[k*3],0,"Core logit0");
            compare_word(l1,logits_expected[k*3+1],1,"Core logit1");
            compare_word(l2,logits_expected[k*3+2],2,"Core logit2");
            check(cls===class_expected[k],"Core class mismatch at DONE");
            @(negedge clk);check(!done && !busy,"DONE must be one clock");
            check(cls===class_expected[k],"Class did not hold after DONE");
        end
    endtask
    initial begin
        $readmemh("conv_all.mem",conv_expected);$readmemh("pool_all.mem",pool_expected);
        $readmemh("logits_all.mem",logits_expected);$readmemh("expected_class.mem",class_expected);
        for(n=0;n<`CNN_NUM_IMAGES*3;n=n+1)check((^logits_expected[n])!==1'bx,"missing expected logits");
        repeat(2)@(negedge clk);rst=0;
        for(n=0;n<16;n=n+1) run_image(n);

        $display("REAL CNN: 16 golden images, latency=%0d clocks",baseline);
        report_test;$finish;
    end
    initial begin #60000000;check(0,"real CNN test timeout");report_test;$finish;end
endmodule
