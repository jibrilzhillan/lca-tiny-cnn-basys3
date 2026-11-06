// tb_cnn_ctrl.v
// U7: state sequence, pulses, busy START rejection, reset and cycle count.
`timescale 1ns/1ps
`include "cnn_params.vh"

// U7: controller-only verification. Engine completion inputs are driven
// independently; no trained weights or arithmetic engines are required.
module tb_cnn_ctrl;
    reg clk, rst, start;
    reg [3:0] img_sel;
    reg conv_done, pool_done, fc_done;
    wire conv_start, pool_start, fc_start, argmax_start;
    wire busy, done;
    wire [3:0] img_sel_q;
    wire [`CNN_CYCLE_WIDTH-1:0] cycle_count;
    wire [5:0] status;
    reg argmax_captured;
    reg [3:0] selected_image;
    reg [`CNN_CYCLE_WIDTH-1:0] saved_count;
    reg [5:0] saved_status;
    integer errors, clock_index, accepted_cycle;
    integer i, stage, completed_runs;

    `include "tb_utils.vh"

    cnn_ctrl dut (
        .clk(clk), .rst(rst), .start(start), .img_sel(img_sel),
        .conv_done(conv_done), .pool_done(pool_done), .fc_done(fc_done),
        .conv_start(conv_start), .pool_start(pool_start),
        .fc_start(fc_start), .argmax_start(argmax_start),
        .busy(busy), .done(done), .img_sel_q(img_sel_q),
        .cycle_count(cycle_count)
    );

    assign status = {busy, done, conv_start, pool_start, fc_start, argmax_start};

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // A separate registered sink verifies the class capture occurs
    // before/at DONE, rather than requiring an extra clock after DONE.
    always @(posedge clk) begin
        clock_index = clock_index + 1;
        if (rst) begin
            argmax_captured <= 1'b0;
        end else if (conv_start) begin
            argmax_captured <= 1'b0;
        end else if (argmax_start) begin
            argmax_captured <= 1'b1;
        end
    end

    task step;
        input [4:0] controls; // {rst,start,conv_done,pool_done,fc_done}
        input [3:0] image;
        begin
            @(negedge clk);
            {rst, start, conv_done, pool_done, fc_done} = controls;
            img_sel = image;
            @(posedge clk);
            #1;
        end
    endtask

    task check_running;
        input [5:0] expected_status;
        reg [`CNN_CYCLE_WIDTH-1:0] expected_count;
        begin
            expected_count = clock_index - accepted_cycle;
            compare_word({26'd0,status}, {26'd0,expected_status}, clock_index, "controller status");
            compare_word({28'd0,img_sel_q}, {28'd0,selected_image}, clock_index, "latched image");
            compare_word({32'd0,cycle_count}, {32'd0,expected_count}, clock_index, "cycle count");
        end
    endtask

    task launch;
        input [3:0] image;
        begin
            selected_image = image;
            step(5'b01000, image);
            accepted_cycle = clock_index;
            check_running(6'b101000);
        end
    endtask

    task run_inference;
        input [3:0] image;
        input integer conv_wait, pool_wait, fc_wait;
        integer j;
        begin
            launch(image);
            // Change image switches and assert START during every busy
            // stage. Completions from the other stages must be ignored.
            for (j=0; j<conv_wait; j=j+1) begin
                step(5'b01011, ~image);
                check_running(6'b100000);
            end
            step(5'b01101, ~image);
            check_running(6'b100100);
            for (j=0; j<pool_wait; j=j+1) begin
                step(5'b01101, ~image);
                check_running(6'b100000);
            end
            step(5'b01110, ~image);
            check_running(6'b100010);
            for (j=0; j<fc_wait; j=j+1) begin
                step(5'b01110, ~image);
                check_running(6'b100000);
            end
            step(5'b01111, ~image);
            check_running(6'b100001);
            step(5'b01111, ~image);
            check_running(6'b010000);
            check(argmax_captured === 1'b1, "DONE asserted before registered argmax capture");
            saved_count = cycle_count;

            // START during DONE is discarded. The next edge returns to
            // IDLE; DONE must not stretch and the final count must hold.
            step(5'b01111, ~image);
            check(status === 6'b000000, "DONE width is not exactly one clock");
            check(cycle_count === saved_count, "counter did not freeze after DONE");
            step(5'b00111, ~image);
            check(status === 6'b000000, "idle engine completions triggered a new run");
            check(cycle_count === saved_count, "idle cycle count did not hold");
            check(img_sel_q === image, "image latch did not hold after DONE");
            completed_runs = completed_runs + 1;
        end
    endtask

    task abort_in_stage;
        input integer target_stage; // 1=CONV, 2=POOL, 3=FC, 4=ARGMAX
        begin
            launch(4'd5);
            if (target_stage >= 2) begin
                step(5'b00100, 4'd9);
                check_running(6'b100100);
            end
            if (target_stage >= 3) begin
                step(5'b00010, 4'd9);
                check_running(6'b100010);
            end
            if (target_stage >= 4) begin
                step(5'b00001, 4'd9);
                check_running(6'b100001);
            end

            saved_status = status;
            @(negedge clk);
            {rst, start, conv_done, pool_done, fc_done} = 5'b11111;
            img_sel = 4'd15;
            #1;
            check(status === saved_status, "reset changed outputs before the rising edge");
            @(posedge clk);
            #1;
            check(status === 6'b000000, "reset did not abort inference or lost priority to START");
            check(cycle_count === 32'd0, "reset did not clear counter");
            check(img_sel_q === 4'd0, "reset did not clear image latch");
            step(5'b00111, 4'd15);
            check(status === 6'b000000, "controller resumed an aborted inference");
            step(5'b00000, 4'd15);
            check(status === 6'b000000, "unexpected launch after reset");
        end
    endtask

    initial begin
        errors=0; clock_index=0; completed_runs=0;
        rst=1; start=0; img_sel=0;
        conv_done=0; pool_done=0; fc_done=0;
        selected_image=0; accepted_cycle=0;
        step(5'b11111, 4'd15);
        check(status === 6'b000000, "initial synchronous reset failed");
        check(cycle_count === 32'd0 && img_sel_q === 4'd0, "initial registers not reset");
        step(5'b00111, 4'd15);
        check(status === 6'b000000, "controller left IDLE without START");

        // All image IDs and varying engine latencies, without reset
        // between successful runs. Includes the shortest completion path.
        for (i=0; i<16; i=i+1) begin
            run_inference(i, i%5, (i*3)%4, (i*7)%6);
        end
        // Exercise the counter near the planned full-inference latency.
        run_inference(4'd10, 89280, 16740, 11160);
        check(`CNN_CYCLE_WIDTH==20,"D20 requires a 20-bit counter");
        check(`CNN_TARGET_CYCLES==120000,"D19 requires a 120000-cycle target");
        check(saved_count<=`CNN_TARGET_CYCLES,"long reference run exceeded latency target");
        check(saved_count>65535, "20-bit counter did not cover a long inference");

        for (stage=1; stage<=4; stage=stage+1) begin
            abort_in_stage(stage);
            run_inference(stage, 2, 1, 3);
        end

        $display("U7: %0d complete runs; reset in CONV/POOL/FC/ARGMAX; busy START rejection; image latch; cycle counter", completed_runs);
        report_test;
        $finish;
    end

    initial begin
        #5000000;
        check(1'b0, "controller test timeout");
        report_test;
        $finish;
    end
endmodule
