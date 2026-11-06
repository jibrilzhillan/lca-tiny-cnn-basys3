// tb_cnn_core_wiring.v
// Opt-in synthetic memory/control wiring test; not CNN golden validation.
`ifdef CNN_CORE_WIRING_TEST
`timescale 1ns/1ps
`include "cnn_params.vh"

// Wiring/memory verification ONLY. This test uses tb/common/mocks/,
// not the real convolution/pooling/FC arithmetic or golden vectors.
module tb_cnn_core_wiring;
    reg clk, rst, start;
    reg [`CNN_IMG_SEL_WIDTH-1:0] img_sel;
    wire busy, done;
    wire [`CNN_CLASS_WIDTH-1:0] class_id;
    wire signed [`CNN_LOGIT_WIDTH-1:0] logit0, logit1, logit2;
    wire [`CNN_CYCLE_WIDTH-1:0] cycle_count;
    reg [7:0] expected_fmap [0:`CNN_NUM_IMAGES*`CNN_FMAP_DEPTH-1];
    reg [7:0] expected_pool [0:`CNN_NUM_IMAGES*`CNN_POOL_DEPTH-1];
    reg [31:0] expected_logits [0:`CNN_NUM_IMAGES*`CNN_NUM_CLASSES-1];
    reg [1:0] expected_class [0:`CNN_NUM_IMAGES-1];
    reg [2:0] class_coverage;
    reg [1:0] previous_class;
    reg [`CNN_CYCLE_WIDTH-1:0] saved_count;
    reg [7:0] saved_fword, saved_pword;
    reg pending_fwrite, pending_pwrite;
    integer saved_faddr, saved_paddr;
    integer errors, clock_index, accepted_cycle;
    integer baseline_latency, complete_runs, image, stage, k;

    `include "tb_utils.vh"

    cnn_core #(.IMAGE_FILE("core_test_images.mem")) dut (
        .clk(clk), .rst(rst), .start(start), .img_sel(img_sel),
        .done(done), .busy(busy), .class_id(class_id),
        .logit0(logit0), .logit1(logit1), .logit2(logit2),
        .cycle_count(cycle_count)
    );

    initial begin clk=0; forever #5 clk=~clk; end
    always @(posedge clk) clock_index=clock_index+1;

    task launch;
        input [3:0] image_id;
        begin
            check(!busy && !done, "launch did not start from IDLE");
            @(negedge clk); start=1; img_sel=image_id;
            @(posedge clk); #1;
            accepted_cycle=clock_index;
            check(busy && !done, "core did not accept START");
            check(dut.img_sel_q===image_id, "image selection was not latched");
            check(cycle_count===32'd0, "cycle count not cleared at START");
            @(negedge clk); start=0; img_sel=~image_id;
        end
    endtask

    task run_image;
        input [3:0] image_id;
        integer index, elapsed;
        begin
            previous_class=class_id;
            launch(image_id);
            while (done !== 1'b1) begin
                @(posedge clk); #1;
                check(dut.img_sel_q===image_id, "live switches changed active image base");
                if (!done) begin
                    check(busy===1'b1, "busy dropped before completion");
                    check(class_id===previous_class, "class changed before DONE");
                end
            end
            elapsed=clock_index-accepted_cycle;
            check(cycle_count===elapsed, "end-to-end cycle count is off by one");
            check(cycle_count<=`CNN_TARGET_CYCLES,"synthetic run exceeded D19 target");
            check(!busy, "busy remained high at DONE");
            check(class_id===expected_class[image_id], "wrong registered class at DONE");
            check(logit0===expected_logits[image_id*3], "logit0 wiring mismatch");
            check(logit1===expected_logits[image_id*3+1], "logit1 wiring mismatch");
            check(logit2===expected_logits[image_id*3+2], "logit2 wiring mismatch");
            if (baseline_latency<0) baseline_latency=elapsed;
            check(elapsed==baseline_latency, "latency varied between image selections");
            for (index=0; index<`CNN_FMAP_DEPTH; index=index+1) begin
                compare_word({24'd0,dut.fmap_ram.mem[index]}, {24'd0,expected_fmap[image_id*`CNN_FMAP_DEPTH+index]}, image_id*`CNN_FMAP_DEPTH+index, "feature-map buffer");
            end
            for (index=0; index<`CNN_POOL_DEPTH; index=index+1) begin
                compare_word({24'd0,dut.pool_ram.mem[index]}, {24'd0,expected_pool[image_id*`CNN_POOL_DEPTH+index]}, image_id*`CNN_POOL_DEPTH+index, "pool buffer");
            end
            class_coverage[class_id]=1'b1;
            complete_runs=complete_runs+1;
            saved_count=cycle_count;
            @(posedge clk); #1;
            check(!busy && !done, "DONE did not return to IDLE in one clock");
            check(cycle_count===saved_count, "cycle counter did not hold in IDLE");
            check(class_id===expected_class[image_id], "class did not hold in IDLE");
        end
    endtask

    task abort_run;
        input integer target_stage;
        begin
            launch(4'd6);
            case (target_stage)
                0: wait(dut.fm_we===1'b1);
                1: wait(dut.pl_we===1'b1);
                2: wait(dut.fc_busy===1'b1);
                3: wait(dut.argmax_start===1'b1);
            endcase
            @(negedge clk);
            pending_fwrite=dut.fm_we;
            pending_pwrite=dut.pl_we;
            saved_faddr=dut.fm_waddr;
            saved_paddr=dut.pl_waddr;
            saved_fword=dut.fmap_ram.mem[saved_faddr];
            saved_pword=dut.pool_ram.mem[saved_paddr];
            rst=1; start=1; img_sel=15;
            @(posedge clk); #1;
            check(!busy && !done, "reset did not abort all stages");
            check(class_id===2'd0 && cycle_count===32'd0, "reset did not clear public results");
            if (pending_fwrite) check(dut.fmap_ram.mem[saved_faddr]===saved_fword, "pending feature-map write was not blocked during reset");
            if (pending_pwrite) check(dut.pool_ram.mem[saved_paddr]===saved_pword, "pending pool write was not blocked during reset");
            @(negedge clk); rst=0; start=0;
            repeat (3) begin
                @(posedge clk); #1;
                check(!busy && !done, "stale engine completion restarted an aborted run");
            end
        end
    endtask

    // Address checking at the memory sampling edge, including final
    // writes coincident with an engine lowering its busy output.
    always @(posedge clk) begin
        if (!rst) begin
            check(dut.img_addr < `CNN_IMAGE_ROM_DEPTH, "image address out of range");
            check(dut.fm_raddr < `CNN_FMAP_DEPTH, "feature-map read address out of range");
            check(dut.pl_raddr < `CNN_POOL_DEPTH, "pool read address out of range");
            if (dut.fm_we) check(dut.fm_waddr < `CNN_FMAP_DEPTH, "feature-map write address out of range");
            if (dut.pl_we) check(dut.pl_waddr < `CNN_POOL_DEPTH, "pool write address out of range");
        end
    end

    initial begin
        errors=0; clock_index=0; baseline_latency=-1; complete_runs=0;
        class_coverage=0; rst=1; start=0; img_sel=0;
        $readmemh("core_expected_fmap.mem", expected_fmap);
        $readmemh("core_expected_pool.mem", expected_pool);
        $readmemh("core_expected_logits.mem", expected_logits);
        $readmemh("core_expected_classes.mem", expected_class);
        for(k=0;k<`CNN_NUM_IMAGES*`CNN_NUM_CLASSES;k=k+1)
            check((^expected_logits[k]) !== 1'bx, "synthetic logit fixture missing or incomplete");
        for(k=0;k<`CNN_NUM_IMAGES;k=k+1)
            check((^expected_class[k]) !== 1'bx, "synthetic class fixture missing or incomplete");
        repeat(2) @(posedge clk);
        @(negedge clk); rst=0;

        for(image=0;image<`CNN_NUM_IMAGES;image=image+1) run_image(image);
        for(stage=0;stage<4;stage=stage+1) begin
            abort_run(stage);
            run_image(stage+3);
        end
        check(class_coverage===3'b111, "synthetic vectors did not exercise all classes");
        check(complete_runs==20, "not all wiring runs completed");
        $display("WIRING ONLY: %0d complete runs, 4 reset recoveries, all buffer words and three classes; latency=%0d cycles", complete_runs,baseline_latency);
        report_test;
        $finish;
    end

    initial begin
        #30000000;
        check(1'b0, "core wiring test timeout");
        report_test;
        $finish;
    end
endmodule
`endif
