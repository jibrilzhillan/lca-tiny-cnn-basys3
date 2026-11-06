// tb_conv_engine_directed.v
// Preserve 5922d44 zero/255/impulse and all-board-image directed coverage.
`ifdef CNN_USE_QUANT_CONFIG
`timescale 1ns/1ps
`include "cnn_params.vh"

module tb_conv_engine_directed;

    // =====================================================
    // PARAMETERS
    // =====================================================
    localparam integer IMG_SIZE =
        `CNN_IMG_WIDTH * `CNN_IMG_HEIGHT;

    localparam integer OUTPUT_SIZE =
        `CNN_FMAP_DEPTH;

    localparam integer OUTPUTS_PER_FILTER =
        `CNN_FMAP_PLANE_SIZE;

    localparam integer NUM_IMAGES =
        `CNN_IMAGE_ROM_DEPTH / IMG_SIZE;

    localparam integer MAX_TIMEOUT = 100000;

    // =====================================================
    // SIGNALS
    // =====================================================
    reg clk;
    reg rst;
    reg start;

    reg [`CNN_IMAGE_ADDR_WIDTH-1:0] img_base;

    wire done;
    wire busy;

    wire [`CNN_IMAGE_ADDR_WIDTH-1:0] img_addr;
    reg  [`CNN_PIXEL_WIDTH-1:0] img_data;

    wire [`CNN_FMAP_ADDR_WIDTH-1:0] fm_waddr;
    wire [`CNN_ACT_WIDTH-1:0] fm_wdata;
    wire fm_we;

    // =====================================================
    // MEMORY
    // =====================================================
    reg [7:0] image_mem [0:`CNN_IMAGE_ROM_DEPTH-1];
    reg [7:0] original_image_mem [0:`CNN_IMAGE_ROM_DEPTH-1];

    reg [7:0] weight_mem [0:`CNN_CONV_W_DEPTH-1];
    reg [31:0] bias_mem [0:`CNN_CONV_B_DEPTH-1];

    // =====================================================
    // TEST COUNTERS
    // =====================================================
    integer write_count;
    integer pass_count;
    integer fail_count;
    integer timeout_count;

    integer total_pass;
    integer total_fail;
    integer total_writes;
    integer test_count;

    integer current_image_base;
    integer expected_addr;

    integer filter_idx;
    integer out_y;
    integer out_x;

    integer i;
    integer j;
    integer image_idx;

    // =====================================================
    // REFERENCE VARIABLES
    // =====================================================
    integer ky;
    integer kx;
    integer tap;
    integer pixel_addr;
    integer weight_idx;

    reg signed [16:0] ref_product;
    reg signed [63:0] ref_acc;
    reg signed [63:0] ref_rounded;

    reg [6:0] expected_activation;

    // =====================================================
    // CLOCK
    // =====================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =====================================================
    // DUT
    // =====================================================
    conv_engine dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .done(done),
        .busy(busy),

        .img_base(img_base),
        .img_addr(img_addr),
        .img_data(img_data),

        .fm_waddr(fm_waddr),
        .fm_wdata(fm_wdata),
        .fm_we(fm_we)
    );

    // =====================================================
    // SYNCHRONOUS IMAGE ROM MODEL
    // =====================================================
    // One-cycle synchronous read latency.
    always @(posedge clk) begin
        img_data <= image_mem[img_addr];
    end

    // =====================================================
    // REFERENCE CALCULATION
    // =====================================================
    task calculate_reference;
        input integer f;
        input integer y;
        input integer x;

        begin
            ref_acc = $signed(bias_mem[f]);

            for (tap = 0; tap < 9; tap = tap + 1) begin

                ky = tap / 3;
                kx = tap % 3;

                pixel_addr =
                    current_image_base +
                    ((y + ky) * `CNN_IMG_WIDTH) +
                    (x + kx);

                weight_idx = (f * 9) + tap;

                ref_product =
                    $signed({1'b0, image_mem[pixel_addr]}) *
                    $signed(weight_mem[weight_idx]);

                ref_acc = ref_acc + ref_product;
            end

            // Requantization with S1 = 9.
            if (`CNN_REQUANT_SHIFT>0)
                ref_rounded=(ref_acc+(64'sd1<<(`CNN_REQUANT_SHIFT-1)))>>>`CNN_REQUANT_SHIFT;
            else ref_rounded=ref_acc;

            // ReLU and saturation.
            if (ref_rounded <= 0)
                expected_activation = 0;
            else if (ref_rounded >= 127)
                expected_activation = 127;
            else
                expected_activation = ref_rounded[6:0];
        end
    endtask

    // =====================================================
    // FEATURE MAP MONITOR
    // =====================================================
    always @(posedge clk) begin
        if (!rst && fm_we) begin

            filter_idx =
                write_count / OUTPUTS_PER_FILTER;

            out_y =
                (write_count % OUTPUTS_PER_FILTER) /
                `CNN_CONV_OUT_WIDTH;

            out_x =
                (write_count % OUTPUTS_PER_FILTER) %
                `CNN_CONV_OUT_WIDTH;

            expected_addr = write_count;

            calculate_reference(
                filter_idx,
                out_y,
                out_x
            );

            if (fm_waddr !== expected_addr) begin
                $display(
                    "FAIL ADDRESS: output=%0d actual=%0d expected=%0d",
                    write_count,
                    fm_waddr,
                    expected_addr
                );
                fail_count = fail_count + 1;
            end
            else if (fm_wdata !== expected_activation) begin
                $display(
                    "FAIL DATA: output=%0d filter=%0d y=%0d x=%0d actual=%0d expected=%0d",
                    write_count,
                    filter_idx,
                    out_y,
                    out_x,
                    fm_wdata,
                    expected_activation
                );
                fail_count = fail_count + 1;
            end
            else begin
                pass_count = pass_count + 1;
            end

            write_count = write_count + 1;
        end
    end

    // =====================================================
    // RESET AND START TASK
    // =====================================================
    task reset_dut;
        begin
            @(negedge clk);
            rst = 1;
            start = 0;

            repeat (3) @(negedge clk);

            rst = 0;
            repeat (2) @(negedge clk);
        end
    endtask

    // =====================================================
    // RUN ONE TEST
    // =====================================================
    task run_test;
        input [255:0] test_name;
        input integer base_addr;

        begin
            $display("");
            $display("--------------------------------------");
            $display("TEST: %0s", test_name);
            $display("--------------------------------------");

            reset_dut();

            current_image_base = base_addr;
            img_base = base_addr;

            write_count = 0;
            pass_count = 0;
            fail_count = 0;
            timeout_count = 0;

            // Start convolution.
            @(negedge clk);
            start = 1;

            @(negedge clk);
            start = 0;

            // Wait for completion.
            while ((done !== 1'b1) &&
                   (timeout_count < MAX_TIMEOUT)) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end

            // Allow final monitor update.
            #2;

            $display("Output writes = %0d", write_count);
            $display("PASS          = %0d", pass_count);
            $display("FAIL          = %0d", fail_count);
            $display("DONE          = %b", done);
            $display("Cycles        = %0d", timeout_count);

            if (done !== 1'b1) begin
                $display("RESULT: FAIL - TIMEOUT");
                total_fail = total_fail + 1;
            end
            else if (write_count != OUTPUT_SIZE) begin
                $display("RESULT: FAIL - OUTPUT COUNT");
                total_fail = total_fail + 1;
            end
            else if (fail_count != 0) begin
                $display("RESULT: FAIL - DATA/ADDRESS");
                total_fail = total_fail + 1;
            end
            else begin
                $display("RESULT: PASS");
                total_pass = total_pass + 1;
            end

            total_writes = total_writes + write_count;
            test_count = test_count + 1;
        end
    endtask

    // =====================================================
    // MAIN TEST SEQUENCE
    // =====================================================
    initial begin

        // Initialize signals.
        rst = 1;
        start = 0;
        img_base = 0;
        img_data = 0;

        write_count = 0;
        pass_count = 0;
        fail_count = 0;
        timeout_count = 0;

        total_pass = 0;
        total_fail = 0;
        total_writes = 0;
        test_count = 0;

        current_image_base = 0;

        // Load memories.
        $readmemh("test_images.mem", image_mem);
        $readmemh("conv_weight.mem", weight_mem);
        $readmemh("conv_bias.mem", bias_mem);

        // Preserve original board images.
        for (i = 0; i < `CNN_IMAGE_ROM_DEPTH; i = i + 1)
            original_image_mem[i] = image_mem[i];

        // -------------------------------------------------
        // TEST 1: ALL-ZERO IMAGE
        // -------------------------------------------------
        for (i = 0; i < IMG_SIZE; i = i + 1)
            image_mem[i] = 8'd0;

        run_test("ALL ZERO IMAGE", 0);

        // -------------------------------------------------
        // TEST 2: ALL-255 IMAGE
        // -------------------------------------------------
        for (i = 0; i < IMG_SIZE; i = i + 1)
            image_mem[i] = 8'd255;

        run_test("ALL 255 IMAGE", 0);

        // -------------------------------------------------
        // TEST 3: IMPULSE IMAGE
        // -------------------------------------------------
        for (i = 0; i < IMG_SIZE; i = i + 1)
            image_mem[i] = 8'd0;

        // Place one bright pixel at the image center.
        image_mem[(16 * `CNN_IMG_WIDTH) + 32] = 8'd255;

        run_test("IMPULSE IMAGE", 0);

        // -------------------------------------------------
        // RESTORE ORIGINAL BOARD IMAGES
        // -------------------------------------------------
        for (i = 0; i < `CNN_IMAGE_ROM_DEPTH; i = i + 1)
            image_mem[i] = original_image_mem[i];

        // -------------------------------------------------
        // TEST 4+: BOARD IMAGES
        // -------------------------------------------------
        for (image_idx = 0;
             image_idx < NUM_IMAGES;
             image_idx = image_idx + 1) begin

            run_test(
                "BOARD IMAGE",
                image_idx * IMG_SIZE
            );
        end

        // -------------------------------------------------
        // FINAL SUMMARY
        // -------------------------------------------------
        $display("");
        $display("======================================");
        $display("       CONV ENGINE FINAL SUMMARY");
        $display("======================================");
        $display("Total test cases = %0d", test_count);
        $display("Test PASS        = %0d", total_pass);
        $display("Test FAIL        = %0d", total_fail);
        $display("Total writes     = %0d", total_writes);
        $display("Expected writes  = %0d",
                 test_count * OUTPUT_SIZE);
        $display("======================================");

        if (total_fail == 0 &&
            total_writes == test_count * OUTPUT_SIZE) begin
            $display("TEST PASSED");
        end
        else begin
            $display("TEST FAILED: Conv directed regression");
        end

        $finish;
    end

endmodule
`endif
