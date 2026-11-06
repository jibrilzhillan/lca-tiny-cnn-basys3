// tb_mac.v
// Latest directed and 10000 random signed MAC tests from 5922d44.

`timescale 1ns / 1ps

module tb_mac;

    reg clk;
    reg rst;

    reg acc_clear;
    reg acc_load;
    reg acc_enable;

    reg [7:0] pixel;
    reg signed [7:0] weight;

    reg signed [23:0] acc_load_data;

    wire signed [23:0] acc;

    reg signed [23:0] expected;

    integer pass_count;
    integer fail_count;
    integer i;

    integer random_pixel;
    integer random_weight;

    reg signed [23:0] expected_product;

    // DUT
    mac uut (
        .clk(clk),
        .rst(rst),
        .acc_clear(acc_clear),
        .acc_load(acc_load),
        .acc_enable(acc_enable),
        .pixel(pixel),
        .weight(weight),
        .acc_load_data(acc_load_data),
        .acc(acc)
    );

    // Clock: 10 ns
    always #5 clk = ~clk;

    // Apply one clock cycle and compare result
    task check_result;
        input [255:0] test_name;
        begin
            @(posedge clk);
            #1;

            if (acc === expected) begin
                pass_count = pass_count + 1;
            end
            else begin
                fail_count = fail_count + 1;

                $display(
                    "FAIL: %0s | Expected = %0d | Actual = %0d",
                    test_name, expected, acc
                );
            end
        end
    endtask

    // Calculate expected MAC result
    task calculate_mac;
        begin
            expected =
                expected +
                ($signed({1'b0, pixel}) * $signed(weight));
        end
    endtask

    initial begin

        // Initialize
        clk = 0;
        rst = 0;

        acc_clear = 0;
        acc_load = 0;
        acc_enable = 0;

        pixel = 0;
        weight = 0;
        acc_load_data = 0;

        expected = 0;

        pass_count = 0;
        fail_count = 0;

        $display("================================");
        $display("       DSP MAC TESTBENCH");
        $display("================================");

        // --------------------------------
        // TEST 1: RESET
        // --------------------------------
        rst = 1;
        expected = 0;
        check_result("RESET");

        rst = 0;

        // --------------------------------
        // TEST 2: LOAD BIAS
        // --------------------------------
        @(negedge clk);
        acc_load = 1;
        acc_load_data = 24'sd1000;
        expected = 24'sd1000;

        check_result("LOAD POSITIVE BIAS");

        acc_load = 0;

        // --------------------------------
        // TEST 3: POSITIVE MULTIPLICATION
        // --------------------------------
        @(negedge clk);
        pixel = 8'd10;
        weight = 8'sd5;
        acc_enable = 1;

        calculate_mac();
        check_result("POSITIVE MULTIPLICATION");

        // --------------------------------
        // TEST 4: NEGATIVE MULTIPLICATION
        // --------------------------------
        @(negedge clk);
        pixel = 8'd20;
        weight = -8'sd3;

        calculate_mac();
        check_result("NEGATIVE MULTIPLICATION");

        // --------------------------------
        // TEST 5: MAXIMUM PIXEL
        // --------------------------------
        @(negedge clk);
        pixel = 8'd255;
        weight = 8'sd127;

        calculate_mac();
        check_result("MAXIMUM POSITIVE INPUT");

        // --------------------------------
        // TEST 6: MINIMUM WEIGHT
        // --------------------------------
        @(negedge clk);
        pixel = 8'd255;
        weight = -8'sd128;

        calculate_mac();
        check_result("MINIMUM NEGATIVE WEIGHT");

        acc_enable = 0;

        // --------------------------------
        // TEST 7: ACCUMULATOR CLEAR
        // --------------------------------
        @(negedge clk);
        acc_clear = 1;
        expected = 0;

        check_result("ACCUMULATOR CLEAR");

        acc_clear = 0;

        // --------------------------------
        // TEST 8: LOAD NEGATIVE BIAS
        // --------------------------------
        @(negedge clk);
        acc_load = 1;
        acc_load_data = -24'sd500;

        expected = -24'sd500;

        check_result("LOAD NEGATIVE BIAS");

        acc_load = 0;

        // --------------------------------
        // TEST 9: ACCUMULATION
        // --------------------------------
        @(negedge clk);
        acc_enable = 1;

        pixel = 8'd10;
        weight = 8'sd2;

        calculate_mac();
        check_result("ACCUMULATION 1");

        @(negedge clk);
        pixel = 8'd20;
        weight = 8'sd3;

        calculate_mac();
        check_result("ACCUMULATION 2");

        @(negedge clk);
        pixel = 8'd30;
        weight = -8'sd4;

        calculate_mac();
        check_result("ACCUMULATION 3");

        acc_enable = 0;

        // --------------------------------
        // TEST 10: RANDOM TEST
        // --------------------------------
        for (i = 0; i < 10000; i = i + 1) begin

            @(negedge clk);

            random_pixel = $random;
            random_weight = $random;

            pixel = random_pixel & 255;
            weight = random_weight;

            acc_enable = 1;

            calculate_mac();
            check_result("RANDOM MAC");

        end

        acc_enable = 0;

        // --------------------------------
        // SUMMARY
        // --------------------------------
        $display("");
        $display("================================");
        $display("       DSP MAC SUMMARY");
        $display("================================");

        $display("TOTAL PASS = %0d", pass_count);
        $display("TOTAL FAIL = %0d", fail_count);

        if (fail_count == 0) begin
            $display("TEST PASSED");
        end
        else begin
            $display("TEST FAILED: %0d errors", fail_count);
        end

        $display("================================");

        $finish;
    end

endmodule