// tb_btn_debounce.v
// Test U8: bouncy presses and releases -> exactly 1 pulse per press, level follows the button.

`timescale 1ns / 1ps

module tb_btn_debounce;

    localparam STABLE   = 16;   // must match btn_debounce with SIM = 1
    localparam N_PRESS  = 50;

    reg  clk = 1'b0;
    reg  btn = 1'b0;
    wire level, rise_p;

    btn_debounce #(.SIM(1)) dut (
        .clk(clk), .btn_in(btn), .btn_level(level), .btn_rise_p(rise_p)
    );

    always #5 clk = ~clk;   // 100 MHz

    integer errors = 0;
    integer pulses = 0;
    integer seed   = 8;
    reg     rise_q = 1'b0;

    // Count pulses and check that each one lasts exactly 1 cycle
    always @(posedge clk) begin
        rise_q <= rise_p;
        if (rise_p) pulses = pulses + 1;
        if (rise_p && rise_q) fail("rise_p high for 2 cycles in a row", 1, 0);
    end

    task fail(input [8*48-1:0] what, input integer expected, input integer actual);
        begin
            errors = errors + 1;
            if (errors <= 10)
                $display("MISMATCH %0d at %0t ns: %0s (expected %0d, actual %0d)",
                         errors, $time, what, expected, actual);
        end
    endtask

    // Toggle the button with random gaps shorter than STABLE, then settle on 'final_val'
    task bounce(input final_val, input integer n_bounces);
        integer i;
        begin
            for (i = 0; i < n_bounces; i = i + 1) begin
                btn = ~btn;
                repeat (1 + {$random(seed)} % (STABLE - 4)) @(posedge clk);
            end
            btn = final_val;
        end
    endtask

    // One summary line per test section: OK, or how many errors it added
    integer section = 0;
    task section_result(input [8*96-1:0] name, input integer errors_before);
        begin
            section = section + 1;
            if (errors == errors_before) $display("check %0d  %0s  OK", section, name);
            else $display("check %0d  %0s  FAILED (%0d errors)", section, name, errors - errors_before);
        end
    endtask

    task check_level(input expected);
        begin
            if (level !== expected) fail("btn_level", expected, level);
        end
    endtask

    integer p, before, e0;
    initial begin
        $display("btn_debounce with SIM = 1: STABLE = %0d cycles", STABLE);
        e0 = errors;
        repeat (40) @(posedge clk);
        check_level(0);
        if (pulses != 0) fail("pulses at power-up", 0, pulses);
        section_result("power-up: level 0, no pulse", e0);

        // 1. A short glitch while released: no pulse, level stays 0
        e0 = errors;
        before = pulses;
        btn = 1'b1; repeat (STABLE / 2) @(posedge clk);
        btn = 1'b0; repeat (3 * STABLE) @(posedge clk);
        if (pulses != before) fail("pulses from a short glitch", 0, pulses - before);
        check_level(0);
        section_result("glitch of STABLE/2 cycles while released: ignored", e0);

        // 2. Clean press and release: 1 pulse, level follows
        e0 = errors;
        before = pulses;
        btn = 1'b1; repeat (3 * STABLE) @(posedge clk);
        check_level(1);
        btn = 1'b0; repeat (3 * STABLE) @(posedge clk);
        check_level(0);
        if (pulses - before != 1) fail("pulses for a clean press", 1, pulses - before);
        section_result("clean press and release: 1 pulse, level follows", e0);

        // 3. Many bouncy presses and releases: exactly 1 pulse each, none on release
        e0 = errors;
        before = pulses;
        for (p = 0; p < N_PRESS; p = p + 1) begin
            before = pulses;
            bounce(1'b1, 1 + {$random(seed)} % 10);
            repeat (STABLE + 4) @(posedge clk);       // held long enough to count
            check_level(1);
            if (pulses - before != 1) fail("pulses for a bouncy press", 1, pulses - before);

            before = pulses;
            bounce(1'b0, 1 + {$random(seed)} % 10);
            repeat (STABLE + 4) @(posedge clk);
            check_level(0);
            if (pulses - before != 0) fail("pulses for a bouncy release", 0, pulses - before);
        end
        section_result("50 bouncy presses + releases: 1 pulse each, none on release", e0);

        $display("%0d checks, %0d pulses in total (expected %0d), no pulse longer than 1 cycle, %0d errors",
                 section, pulses, N_PRESS + 1, errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule
