// tb_classifier_core.v
// Classifier integration verification.
// Real Pool/FC/Argmax with the core; only Conv remains synthetic.
`ifdef CNN_CORE_WIRING_TEST
`timescale 1ns/1ps
`include "cnn_params.vh"
module tb_classifier_core;
    reg clk=0,rst=1,start=0;
    always #5 clk=~clk;
    reg [3:0] image=0;
    wire busy,done;
    wire [1:0] class_id;
    wire signed [31:0] l0,l1,l2;
    wire [`CNN_CYCLE_WIDTH-1:0] count;
    reg [7:0] expected_pool[0:`CNN_NUM_IMAGES*`CNN_POOL_DEPTH-1];
    reg signed [31:0] expected_logits[0:47];
    integer errors=0,n,i,cycles,baseline=-1,winner;
    `include "tb_utils.vh"
    cnn_core #(.IMAGE_FILE("classifier_core_images.mem")) dut(
        .clk(clk),.rst(rst),.start(start),.img_sel(image),.busy(busy),.done(done),
        .class_id(class_id),.logit0(l0),.logit1(l1),.logit2(l2),.cycle_count(count));
    task run_image;
        input integer k;
        begin
            @(negedge clk); image=k; start=1;
            @(negedge clk); start=0; image=15-k; cycles=0;
            while(!done && cycles<200001) begin @(negedge clk); cycles=cycles+1; end
            check(done && !busy,"Core timeout or busy at DONE");
            check(count==cycles,"Core cycle count mismatch");
            check(count<=`CNN_TARGET_CYCLES,"partial integration exceeded D19 target");
            if(baseline<0) baseline=count;
            check(count==baseline,"Core latency varies by image");
            for(i=0;i<`CNN_POOL_DEPTH;i=i+1)
                compare_word({24'd0,dut.pool_ram.mem[i]}, {24'd0,expected_pool[k*`CNN_POOL_DEPTH+i]},i,"Core pool");
            compare_word(l0,expected_logits[k*3],k*3,"Core logit0");
            compare_word(l1,expected_logits[k*3+1],k*3+1,"Core logit1");
            compare_word(l2,expected_logits[k*3+2],k*3+2,"Core logit2");
            winner=0;
            if(expected_logits[k*3+1]>expected_logits[k*3]) winner=1;
            if(expected_logits[k*3+2]>expected_logits[k*3+winner]) winner=2;
            check(class_id===winner[1:0],"Core class not valid together with DONE");
            @(negedge clk); check(!done && !busy,"Core DONE width mismatch");
        end
    endtask
    initial begin
        $readmemh("classifier_core_pool.mem",expected_pool);
        $readmemh("classifier_core_logits.mem",expected_logits);
        repeat(2) @(negedge clk); rst=0;
        for(n=0;n<16;n=n+1) run_image(n);
        @(negedge clk); start=1;
        @(negedge clk); start=0;
        wait(dut.fc_busy); @(negedge clk); rst=1;
        @(negedge clk); check(!busy && !done && count==0,"Core reset failed");
        rst=0; repeat(3) @(negedge clk); run_image(3);
        $display("PARTIAL INTEGRATION: 16 images + reset recovery, real classifier, mock Conv; latency=%0d",baseline);
        report_test; $finish;
    end
    initial begin #30000000; check(0,"Core integration timeout"); report_test; $finish; end
endmodule
`endif
