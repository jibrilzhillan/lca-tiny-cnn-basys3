// tb_result_display.v
// Testbench for result_display: LEDs and digit patterns before the first run, for each class,
// PASS/FAIL, BUSY, latency mode, reset, and that the result holds when the inputs change.

`timescale 1ns / 1ps

module tb_result_display;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg         rst = 1'b1;
    reg  [1:0]  class_id = 2'd0;
    reg         done_p = 1'b0;
    reg         busy = 1'b0;
    reg  [1:0]  label = 2'd0;
    reg  [3:0]  img_sel = 4'd0;
    reg  [19:0] cycle_count = 20'h00000;
    reg         cyc_hi = 0;
    reg         mode = 1'b0;
    wire [15:0] led;
    wire [6:0]  d0, d1, d2, d3;
    wire [3:0]  dp_n;

    result_display dut (
        .clk(clk), .rst(rst), .class_id(class_id), .done_p(done_p), .busy(busy),
        .label(label), .img_sel(img_sel), .cycle_count(cycle_count), .mode(mode), .cyc_hi(cyc_hi),
        .led(led), .digit0_n(d0), .digit1_n(d1), .digit2_n(d2), .digit3_n(d3), .dp_n(dp_n)
    );

    // Expected patterns, active low, g f e d c b a
    localparam [6:0] L = 7'b1000111, F = 7'b0001110, S = 7'b0010010, T = 7'b0000111,
                     R = 7'b0101111, DASH = 7'b0111111, BLANK = 7'b1111111;
    localparam [6:0] H0 = 7'b1000000, H1 = 7'b1111001, H2 = 7'b0100100, H3 = 7'b0110000,
                     H5 = 7'b0010010, H7 = 7'b1111000, HA = 7'b0001000, HB = 7'b0000011,
                     HC = 7'b1000110, HD = 7'b0100001, HF = 7'b0001110;

    // LED groups
    localparam [15:0] BAR_L = 16'b1110_0000_0000_0000, BAR_S = 16'b0000_0001_1000_0000,
                      BAR_R = 16'b0000_0000_0000_0111, PASS = 16'h0800, FAIL = 16'h0400,
                      DONE = 16'h0010, BUSY = 16'h0008;

    integer errors = 0;
    integer step = 0;

    task check(input [16*8-1:0] what, input [15:0] exp_led,
               input [6:0] e3, input [6:0] e2, input [6:0] e1, input [6:0] e0);
        begin
            step = step + 1;
            if (led !== exp_led || d3 !== e3 || d2 !== e2 || d1 !== e1 || d0 !== e0 || dp_n !== 4'b1111) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("MISMATCH %0d (step %0d, %0s): led expected %h actual %h | digits expected %b %b %b %b actual %b %b %b %b",
                             errors, step, what, exp_led, led, e3, e2, e1, e0, d3, d2, d1, d0);
            end else begin
                $display("check %0d  %0s: led %h, digits %b %b %b %b  OK", step, what, led, d3, d2, d1, d0);
            end
        end
    endtask

    task run_done(input [1:0] cls);
        begin
            class_id = cls;
            @(posedge clk); done_p = 1'b1;
            @(posedge clk); done_p = 1'b0;
            repeat (2) @(posedge clk); #1;      // captured, then LEDs registered
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst = 1'b0;
        img_sel = 4'h5;
        repeat (2) @(posedge clk); #1;

        // Before any run: dashes, image index on digit 3, no LEDs
        check("before run", 16'h0000, H5, BLANK, DASH, DASH);

        // Busy shows on LED 3 only
        busy = 1'b1; repeat (2) @(posedge clk); #1;
        check("busy", BUSY, H5, BLANK, DASH, DASH);
        busy = 1'b0;

        // LEFT, matches the label -> PASS
        label = 2'd0; run_done(2'd0);
        check("LEFT pass", BAR_L | PASS | DONE, H5, BLANK, L, F);

        // STRAIGHT, label LEFT -> FAIL
        run_done(2'd1);
        check("STRAIGHT fail", BAR_S | FAIL | DONE, H5, BLANK, S, T);

        // RIGHT, matches -> PASS
        label = 2'd2; run_done(2'd2);
        check("RIGHT pass", BAR_R | PASS | DONE, H5, BLANK, R, T);

        // Result holds when class_id, label and switches change without a new done
        class_id = 2'd0; label = 2'd1; img_sel = 4'hA;
        repeat (2) @(posedge clk); #1;
        check("hold", BAR_R | PASS | DONE, HA, BLANK, R, T);

        // Latency mode: 4 hex digits of cycle_count, LEDs unchanged
        cycle_count = 16'h5DB0; mode = 1'b1; #1;
        check("latency 5DB0", BAR_R | PASS | DONE, H5, HD, HB, H0);
        cycle_count = 16'hF17C; #1;
        check("latency F17C", BAR_R | PASS | DONE, HF, H1, H7, HC);
        cycle_count=20'h19E3A;cyc_hi=1;#1;
        check("latency high",BAR_R | PASS | DONE,H0,H0,H0,H1);
        cycle_count=20'hF0000;#1;
        check("latency max page",BAR_R | PASS | DONE,H0,H0,H0,HF);
        cyc_hi=0;
        mode = 1'b0; #1;

        // Reset clears the result
        rst = 1'b1; repeat (2) @(posedge clk); rst = 1'b0; repeat (2) @(posedge clk); #1;
        check("after reset", 16'h0000, HA, BLANK, DASH, DASH);

        $display("%0d checks, %0d errors", step, errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule
