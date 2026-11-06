// tb_fc_engine.v
// U5: internal clocked ROMs, real RAM, signed extrema, biases and reset.
`timescale 1ns/1ps
`include "cnn_params.vh"
module tb_fc_engine;
    reg clk=0,rst=1,start=0;
    always #5 clk=~clk;
    wire busy,done;
    wire [`CNN_POOL_ADDR_WIDTH-1:0] address;
    wire [7:0] data;
    wire signed [31:0] l0,l1,l2;
    reg [7:0] inputs[0:5*`CNN_FC_INPUTS-1];
    reg [31:0] expected[0:14];
    integer errors=0,n,i,cycles;
    `include "tb_utils.vh"
    fc_engine #(.WEIGHT_FILE("classifier_fc_w.mem"),.BIAS_FILE("classifier_fc_b.mem")) dut(
        .clk(clk),.rst(rst),.start(start),.busy(busy),.done(done),
        .pl_raddr(address),.pl_rdata(data),.logit0(l0),.logit1(l1),.logit2(l2));
    ram #(.DEPTH(`CNN_FC_INPUTS),.ADDR_WIDTH(`CNN_POOL_ADDR_WIDTH)) source(
        .clk(clk),.we(1'b0),.waddr({`CNN_POOL_ADDR_WIDTH{1'b0}}),.wdata(8'd0),.raddr(address),.rdata(data));
    always @(posedge clk) if(!rst) begin
        check(address<`CNN_FC_INPUTS,"FC pool address out of range");
        check(dut.weight_addr<`CNN_FC_W_DEPTH,"FC weight address out of range");
        check(dut.class_idx<3,"FC bias address out of range");
    end
    task run_case;
        input integer k;
        begin
            @(negedge clk);
            for(i=0;i<`CNN_FC_INPUTS;i=i+1) source.mem[i]=inputs[k*`CNN_FC_INPUTS+i];
            start=1; @(negedge clk); start=0;
            check(busy && !done,"FC did not accept START");
            repeat(11) @(negedge clk);
            start=1; @(negedge clk); start=0;
            cycles=0;
            while(!done && cycles<15000) begin @(negedge clk); cycles=cycles+1; end
            check(done && !busy,"FC timeout or busy at DONE");
            compare_word(l0,expected[k*3],k*3,"FC logit0");
            compare_word(l1,expected[k*3+1],k*3+1,"FC logit1");
            compare_word(l2,expected[k*3+2],k*3+2,"FC logit2");
            @(negedge clk); check(!done && !busy,"FC DONE must be one clock");
            compare_word(l2,expected[k*3+2],k*3+2,"FC hold");
        end
    endtask
    initial begin
        $readmemh("classifier_fc_input.mem",inputs); $readmemh("classifier_fc_expected.mem",expected);
        repeat(2) @(negedge clk); rst=0;
        for(n=0;n<5;n=n+1) run_case(n);
        @(negedge clk); start=1;
        @(negedge clk); start=0;
        repeat(21) @(negedge clk);
        rst=1; @(negedge clk);
        check(!busy && !done && l0===0 && l1===0 && l2===0,"FC reset failed");
        rst=0; repeat(3) @(negedge clk);
        check(!busy && !done,"FC resumed an aborted run");
        run_case(2); report_test; $finish;
    end
    initial begin #5000000; check(0,"FC global timeout"); report_test; $finish; end
endmodule
