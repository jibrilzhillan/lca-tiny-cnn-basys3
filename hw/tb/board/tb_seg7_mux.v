// tb_seg7_mux.v
// Test U9: digits scan 0 -> 1 -> 2 -> 3 in order, one anode at a time, each showing its own
// pattern; hex_to_7seg decode table checked against an independently written table.

`timescale 1ns / 1ps

module tb_seg7_mux;

    localparam DIGIT_CYCLES = 4;     // seg7_mux with SIM = 1: 2^2 cycles per digit
    localparam N_SCANS      = 20;    // full 4-digit scans to check

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    integer errors = 0;
    task fail(input [8*40-1:0] what, input integer idx, input integer expected, input integer actual);
        begin
            errors = errors + 1;
            if (errors <= 10)
                $display("MISMATCH %0d at %0t ns: %0s [%0d] expected 'h%0h, actual 'h%0h",
                         errors, $time, what, idx, expected, actual);
        end
    endtask

    // ---------------------------------------------------------------- Part 1: hex_to_7seg table
    // Expected segments written in the other bit order, active high: {a,b,c,d,e,f,g}
    reg  [3:0] hex;
    wire [6:0] hex_seg_n;
    hex_to_7seg u_dec (.hex(hex), .seg(hex_seg_n));

    function [6:0] abcdefg_to_seg_n(input [6:0] abcdefg);   // -> active low, bit 0 = a
        integer i;
        begin
            for (i = 0; i < 7; i = i + 1)
                abcdefg_to_seg_n[i] = ~abcdefg[6 - i];
        end
    endfunction

    reg [6:0] exp_abcdefg [0:15];
    initial begin
        exp_abcdefg[4'h0] = 7'b1111110;  exp_abcdefg[4'h1] = 7'b0110000;
        exp_abcdefg[4'h2] = 7'b1101101;  exp_abcdefg[4'h3] = 7'b1111001;
        exp_abcdefg[4'h4] = 7'b0110011;  exp_abcdefg[4'h5] = 7'b1011011;
        exp_abcdefg[4'h6] = 7'b1011111;  exp_abcdefg[4'h7] = 7'b1110000;
        exp_abcdefg[4'h8] = 7'b1111111;  exp_abcdefg[4'h9] = 7'b1111011;
        exp_abcdefg[4'hA] = 7'b1110111;  exp_abcdefg[4'hB] = 7'b0011111;
        exp_abcdefg[4'hC] = 7'b1001110;  exp_abcdefg[4'hD] = 7'b0111101;
        exp_abcdefg[4'hE] = 7'b1001111;  exp_abcdefg[4'hF] = 7'b1000111;
    end

    // ---------------------------------------------------------------- Part 2: seg7_mux scan
    reg  [6:0] digit_n [0:3];
    reg  [3:0] dp_in_n;
    wire [6:0] seg_n;
    wire       dp_n;
    wire [3:0] an_n;

    seg7_mux #(.SIM(1)) dut (
        .clk(clk), .rst(rst),
        .digit0_n(digit_n[0]), .digit1_n(digit_n[1]), .digit2_n(digit_n[2]), .digit3_n(digit_n[3]),
        .dp_in_n(dp_in_n),
        .seg_n(seg_n), .dp_n(dp_n), .an_n(an_n)
    );

    // Which digit is lit: -1 = none, -2 = more than one
    function integer active_digit(input [3:0] an);
        begin
            case (an)
                4'b1110: active_digit = 0;
                4'b1101: active_digit = 1;
                4'b1011: active_digit = 2;
                4'b0111: active_digit = 3;
                4'b1111: active_digit = -1;
                default: active_digit = -2;
            endcase
        end
    endfunction

    // One summary line per test part: OK, or how many errors it added
    integer section = 0;
    task section_result(input [8*96-1:0] name, input integer errors_before);
        begin
            section = section + 1;
            if (errors == errors_before) $display("check %0d  %0s  OK", section, name);
            else $display("check %0d  %0s  FAILED (%0d errors)", section, name, errors - errors_before);
        end
    endtask

    integer d, prev_d, run_len, changes, i, e0, cycles_checked;
    initial begin
        // Part 1
        e0 = errors;
        for (i = 0; i < 16; i = i + 1) begin
            hex = i; #1;
            if (hex_seg_n !== abcdefg_to_seg_n(exp_abcdefg[i]))
                fail("hex_to_7seg", i, abcdefg_to_seg_n(exp_abcdefg[i]), hex_seg_n);
        end
        section_result("hex_to_7seg: all 16 patterns (0-F) match the reference table", e0);

        // Part 2: four different patterns and one decimal point, so a wrong mux is visible
        digit_n[0] = 7'b1000000;   // "0"
        digit_n[1] = 7'b1111001;   // "1"
        digit_n[2] = 7'b0100100;   // "2"
        digit_n[3] = 7'b0110000;   // "3"
        dp_in_n    = 4'b1011;      // dp lit on digit 2 only

        e0 = errors;
        repeat (3) @(posedge clk);
        #1;
        if (an_n !== 4'b1111) fail("an_n during reset", 0, 4'b1111, an_n);
        section_result("reset: all digits off", e0);
        rst = 1'b0;

        e0 = errors;
        prev_d = -1; run_len = 0; changes = 0; cycles_checked = 0;
        repeat (N_SCANS * 4 * DIGIT_CYCLES + 2) begin
            @(posedge clk); #1;
            cycles_checked = cycles_checked + 1;
            d = active_digit(an_n);
            if (d == -2) begin
                fail("more than one anode low", 0, 0, an_n);
            end else if (d >= 0) begin
                if (seg_n !== digit_n[d]) fail("seg_n for digit", d, digit_n[d], seg_n);
                if (dp_n  !== dp_in_n[d]) fail("dp_n for digit", d, dp_in_n[d], dp_n);
                if (d != prev_d) begin
                    if (prev_d >= 0 && d != (prev_d + 1) % 4)
                        fail("scan order: digit after", prev_d, (prev_d + 1) % 4, d);
                    if (prev_d >= 0 && changes > 1 && run_len != DIGIT_CYCLES)
                        fail("cycles on digit", prev_d, DIGIT_CYCLES, run_len);
                    changes = changes + 1;
                    run_len = 1;
                end else begin
                    run_len = run_len + 1;
                end
                prev_d = d;
            end
        end
        if (changes < N_SCANS * 4) fail("digit changes seen", 0, N_SCANS * 4, changes);
        $display("scan: %0d cycles checked, %0d digit changes (%0d full scans), %0d cycles per digit",
                 cycles_checked, changes, changes / 4, DIGIT_CYCLES);
        section_result("scan: one anode at a time, order 0-1-2-3, right pattern and dp per digit", e0);

        $display("%0d checks, %0d errors", section, errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule
