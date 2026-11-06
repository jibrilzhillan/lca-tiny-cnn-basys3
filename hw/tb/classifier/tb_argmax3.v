// tb_argmax3.v
// U6: clocked signed argmax, all ties, extreme values and random triples.
`timescale 1ns/1ps
module tb_argmax3;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg signed [31:0] a=0,b=0,c=0;
    wire [1:0] result;
    reg [1:0] previous;
    integer errors=0,i,seed=45678;
    `include "tb_utils.vh"
    argmax3 dut(.clk(clk),.rst(rst),.logit0(a),.logit1(b),.logit2(c),.class_id(result));
    task sample;
        input signed [31:0] x,y,z;
        integer winner;
        reg signed [31:0] maximum;
        begin
            @(negedge clk); previous=result; a=x; b=y; c=z;
            winner=0; maximum=x;
            if(y>maximum) begin maximum=y; winner=1; end
            if(z>maximum) winner=2;
            #1; check(result===previous,"Argmax changed before rising clock edge");
            @(posedge clk); #1;
            compare_word({30'd0,result},winner,i,"Argmax");
        end
    endtask
    initial begin
        repeat(2) @(negedge clk); rst=0;
        sample(1,0,0); sample(0,1,0); sample(0,0,1);
        sample(5,5,1); sample(5,1,5); sample(1,5,5); sample(5,5,5);
        sample(-4,-3,-2); sample(32'sh80000000,0,32'sh7fffffff);
        sample(32'sh80000000,32'sh80000000,32'sh80000000);
        for(i=0;i<1000;i=i+1) sample($random(seed),$random(seed),$random(seed));
        sample(0,1,9);
        @(negedge clk); rst=1; #1;
        check(result===2,"Argmax reset must be synchronous");
        @(posedge clk); #1; check(result===0,"Argmax reset did not clear result");
        report_test; $finish;
    end
    initial begin #100000; check(0,"Argmax timeout"); report_test; $finish; end
endmodule
