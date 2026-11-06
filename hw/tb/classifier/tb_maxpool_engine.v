// tb_maxpool_engine.v
// U4: real synchronous RAM, all output words, repeated runs and reset.
`timescale 1ns/1ps
`include "cnn_params.vh"
module tb_maxpool_engine;
    reg clk=0, rst=1, start=0;
    always #5 clk=~clk;
    wire busy,done,we;
    wire [`CNN_FMAP_ADDR_WIDTH-1:0] ra;
    wire [`CNN_POOL_ADDR_WIDTH-1:0] wa;
    wire [7:0] rd,wd;
    reg [7:0] inputs[0:7*`CNN_FMAP_DEPTH-1], expected[0:7*`CNN_POOL_DEPTH-1];
    integer errors=0, case_id, i, writes=0, cycle=0;
    `include "tb_utils.vh"
    maxpool_engine dut(.clk(clk),.rst(rst),.start(start),.busy(busy),.done(done),
        .fm_raddr(ra),.fm_rdata(rd),.pl_waddr(wa),.pl_wdata(wd),.pl_we(we));
    ram #(.DEPTH(`CNN_FMAP_DEPTH),.ADDR_WIDTH(`CNN_FMAP_ADDR_WIDTH)) source(
        .clk(clk),.we(1'b0),.waddr({`CNN_FMAP_ADDR_WIDTH{1'b0}}),.wdata(8'd0),.raddr(ra),.rdata(rd));
    ram #(.DEPTH(`CNN_POOL_DEPTH),.ADDR_WIDTH(`CNN_POOL_ADDR_WIDTH)) destination(
        .clk(clk),.we(we && !rst),.waddr(wa),.wdata(wd),.raddr({`CNN_POOL_ADDR_WIDTH{1'b0}}),.rdata());
    always @(posedge clk) if(!rst) begin
        check(ra<`CNN_FMAP_DEPTH,"Pool read address out of range");
        if(we) begin
            check(wa==writes,"Pool writes must visit every address once in order");
            writes=writes+1;
        end
    end
    task run_case;
        input integer n;
        begin
            @(negedge clk);
            for(i=0;i<`CNN_FMAP_DEPTH;i=i+1) source.mem[i]=inputs[n*`CNN_FMAP_DEPTH+i];
            writes=0; start=1;
            @(negedge clk); start=0;
            check(busy && !done,"Pool did not accept START");
            repeat(7) @(negedge clk);
            start=1; @(negedge clk); start=0;
            cycle=0;
            while(!done && cycle<20000) begin @(negedge clk); cycle=cycle+1; end
            check(done && !busy,"Pool timed out or remained busy");
            check(writes==`CNN_POOL_DEPTH,"Pool did not commit all `CNN_POOL_DEPTH writes before DONE");
            for(i=0;i<`CNN_POOL_DEPTH;i=i+1)
                compare_word({24'd0,destination.mem[i]}, {24'd0,expected[n*`CNN_POOL_DEPTH+i]},i,"Pool");
            @(negedge clk); check(!done && !busy,"Pool DONE must be one clock");
        end
    endtask
    initial begin
        $readmemh("classifier_pool_input.mem",inputs);
        $readmemh("classifier_pool_expected.mem",expected);
        repeat(2) @(negedge clk); rst=0;
        for(case_id=0;case_id<7;case_id=case_id+1) run_case(case_id);
        // Abort with a pending output write, then fully overwrite buffers.
        @(negedge clk); start=1;
        @(negedge clk); start=0;
        wait(we); @(negedge clk); rst=1;
        @(negedge clk); check(!busy && !done && !we,"Pool reset failed");
        rst=0; repeat(3) @(negedge clk);
        check(!busy && !done,"Pool resumed an aborted run");
        run_case(0);
        report_test; $finish;
    end
    initial begin #5000000; check(0,"Pool global timeout"); report_test; $finish; end
endmodule
