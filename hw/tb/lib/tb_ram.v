// tb_ram.v
// Verify RAM ports, initialization, read-first collisions and styles.
`timescale 1ns/1ps
`include "cnn_params.vh"
module tb_ram;
    reg clk, we, pool_we, wide_we;
    reg [`CNN_FMAP_ADDR_WIDTH-1:0] waddr, raddr;
    reg [`CNN_POOL_ADDR_WIDTH-1:0] pool_waddr, pool_raddr;
    reg [1:0] wide_waddr, wide_raddr;
    reg [7:0] wdata, pool_wdata, held;
    reg [31:0] wide_wdata;
    wire [7:0] rdata, pool_rdata;
    wire [31:0] wide_rdata;
    reg [31:0] expected_bias [0:2];
    integer errors, i;

    `include "tb_utils.vh"

    ram #(.DATA_WIDTH(8),.ADDR_WIDTH(`CNN_FMAP_ADDR_WIDTH),.DEPTH(`CNN_FMAP_DEPTH),.RAM_STYLE("block")) fmap_ram
        (.clk(clk),.we(we),.waddr(waddr),.wdata(wdata),.raddr(raddr),.rdata(rdata));
    ram #(.DATA_WIDTH(8),.ADDR_WIDTH(`CNN_POOL_ADDR_WIDTH),.DEPTH(`CNN_POOL_DEPTH),.RAM_STYLE("distributed")) pool_ram
        (.clk(clk),.we(pool_we),.waddr(pool_waddr),.wdata(pool_wdata),.raddr(pool_raddr),.rdata(pool_rdata));
    ram #(.DATA_WIDTH(32),.ADDR_WIDTH(2),.DEPTH(3),.INIT_FILE("memory_test_s32.mem"),.RAM_STYLE("distributed")) wide_ram
        (.clk(clk),.we(wide_we),.waddr(wide_waddr),.wdata(wide_wdata),.raddr(wide_raddr),.rdata(wide_rdata));

    function [7:0] pattern;
        input integer index;
        begin pattern=index*73+19; end
    endfunction
    function [7:0] pool_pattern;
        input integer index;
        begin pool_pattern=index*29+7; end
    endfunction

    initial begin clk=0; forever #5 clk=~clk; end
    initial begin
        errors=0; we=0; pool_we=0; wide_we=0;
        waddr=0; raddr=0; pool_waddr=0; pool_raddr=0;
        wide_waddr=0; wide_raddr=0; wdata=0; pool_wdata=0; wide_wdata=0;
        $readmemh("memory_test_s32.mem",expected_bias);
        for(i=0;i<3;i=i+1) begin
            check((^expected_bias[i]) !== 1'bx,"RAM init fixture missing or incomplete");
            @(negedge clk); wide_raddr=i;
            @(posedge clk); #1;
            compare_word(wide_rdata,expected_bias[i],i,"initialized 32-bit RAM");
        end
        for(i=0;i<`CNN_FMAP_DEPTH;i=i+1) begin
            @(negedge clk); we=1; waddr=i; wdata=pattern(i);
            if(i<`CNN_POOL_DEPTH) begin pool_we=1; pool_waddr=i; pool_wdata=pool_pattern(i); end
            else pool_we=0;
            @(posedge clk); #1;
        end
        for(i=0;i<`CNN_FMAP_DEPTH;i=i+1) begin
            @(negedge clk); held=rdata; we=0; waddr=i; wdata=0; raddr=i;
            pool_we=0;
            if(i<`CNN_POOL_DEPTH) begin pool_waddr=i; pool_wdata=0; pool_raddr=i; end
            #1;
            compare_word({24'd0,rdata},{24'd0,held},i,"RAM holds before clock");
            @(posedge clk); #1;
            compare_word({24'd0,rdata},{24'd0,pattern(i)},i,"fmap RAM / write disabled");
            if(i<`CNN_POOL_DEPTH) compare_word({24'd0,pool_rdata},{24'd0,pool_pattern(i)},i,"pool RAM / write disabled");
        end
        // First and last addresses: same-edge read returns the old word.
        for(i=0;i<`CNN_FMAP_DEPTH;i=i+(`CNN_FMAP_DEPTH-1)) begin
            @(negedge clk); we=1; waddr=i; raddr=i; wdata=8'ha5;
            @(posedge clk); #1;
            compare_word({24'd0,rdata},{24'd0,pattern(i)},i,"read-first fmap collision");
            @(negedge clk); we=0;
            @(posedge clk); #1;
            compare_word({24'd0,rdata},32'ha5,i,"fmap new value");
        end
        for(i=0;i<`CNN_POOL_DEPTH;i=i+(`CNN_POOL_DEPTH-1)) begin
            @(negedge clk); pool_we=1; pool_waddr=i; pool_raddr=i; pool_wdata=8'h5a;
            @(posedge clk); #1;
            compare_word({24'd0,pool_rdata},{24'd0,pool_pattern(i)},i,"read-first pool collision");
            @(negedge clk); pool_we=0;
            @(posedge clk); #1;
            compare_word({24'd0,pool_rdata},32'h5a,i,"pool new value");
        end
        @(negedge clk); we=1; waddr=100; wdata=8'h3c; raddr=0;
        @(posedge clk); #1;
        compare_word({24'd0,rdata},32'ha5,0,"independent read/write ports");
        @(negedge clk); we=0; raddr=100;
        @(posedge clk); #1;
        compare_word({24'd0,rdata},32'h3c,100,"independent write persisted");
        @(negedge clk); wide_we=1; wide_waddr=1; wide_raddr=1; wide_wdata=32'hfffffffe;
        @(posedge clk); #1;
        compare_word(wide_rdata,32'd0,1,"32-bit read-first collision");
        @(negedge clk); wide_we=0;
        @(posedge clk); #1;
        compare_word(wide_rdata,32'hfffffffe,1,"32-bit updated word");
        report_test;
        $finish;
    end
    initial begin
        #1000000;
        check(1'b0,"RAM test timeout"); report_test; $finish;
    end
endmodule
