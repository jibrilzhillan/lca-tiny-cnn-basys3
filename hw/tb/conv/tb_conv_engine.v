// tb_conv_engine.v
// U3/U10/I1: all 16 images, every read/write address and golden activation.
`timescale 1ns/1ps
`include "cnn_params.vh"

module tb_conv_engine;

    // =====================================================
    // PARAMETERS
    // =====================================================
    localparam integer IMAGE_WIDTH  = 64;
    localparam integer IMAGE_HEIGHT = 32;
    localparam integer IMAGE_SIZE   = IMAGE_WIDTH * IMAGE_HEIGHT;

    localparam integer KERNEL_SIZE  = 3;
    localparam integer NUM_FILTERS  = 4;

    localparam integer OUT_WIDTH    = IMAGE_WIDTH - KERNEL_SIZE + 1;
    localparam integer OUT_HEIGHT   = IMAGE_HEIGHT - KERNEL_SIZE + 1;
    localparam integer OUT_PER_FILTER = OUT_WIDTH * OUT_HEIGHT;
    localparam integer TOTAL_OUTPUTS = NUM_FILTERS * OUT_PER_FILTER;

    localparam integer NUM_IMAGES = 16;

    // =====================================================
    // DUT SIGNALS
    // =====================================================
    reg clk;
    reg rst;
    reg start;

    reg [`CNN_IMAGE_ADDR_WIDTH-1:0] img_base;
    reg [`CNN_PIXEL_WIDTH-1:0] img_data;

    wire [`CNN_IMAGE_ADDR_WIDTH-1:0] img_addr;

    wire [`CNN_FMAP_ADDR_WIDTH-1:0] fm_waddr;
    wire [`CNN_ACT_WIDTH-1:0] fm_wdata;

    wire fm_we;
    wire done;
    wire busy;

    // =====================================================
    // MEMORY
    // =====================================================
    reg [`CNN_PIXEL_WIDTH-1:0] image_mem [0:32767];

    reg signed [7:0] weight_mem [0:35];
    reg signed [31:0] bias_mem [0:3];

    // =====================================================
    // TEST VARIABLES
    // =====================================================
    integer image_index;
    integer total_pass;
    integer total_fail;
    integer total_writes;

    integer image_pass;
    integer image_fail;
    integer image_writes;

    integer filter_index;
    integer output_row;
    integer output_col;

    reg [`CNN_ACT_WIDTH-1:0] expected;

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
    // CLOCK GENERATOR
    // =====================================================
    always #5 clk = ~clk;

    // =====================================================
    // SYNCHRONOUS IMAGE ROM MODEL
    // =====================================================
    always @(posedge clk) begin
        img_data <= image_mem[img_addr];
    end

    // =====================================================
    // REFERENCE CONVOLUTION
    // =====================================================
    function [`CNN_ACT_WIDTH-1:0] reference_conv;

        input integer base;
        input integer filter;
        input integer row;
        input integer col;

        integer ky;
        integer kx;
        integer addr;

        integer pixel_value;
        integer weight_value;

        reg signed [31:0] acc_ref;
        reg signed [31:0] scaled;

        begin
            acc_ref = bias_mem[filter];

            // 3x3 convolution
            for (ky = 0; ky < KERNEL_SIZE; ky = ky + 1) begin
                for (kx = 0; kx < KERNEL_SIZE; kx = kx + 1) begin

                    addr = base
                         + ((row + ky) * IMAGE_WIDTH)
                         + (col + kx);

                    pixel_value = image_mem[addr];
                    weight_value = weight_mem[
                        filter * 9 + ky * 3 + kx
                    ];

                    acc_ref = acc_ref
                            + (pixel_value * weight_value);
                end
            end

            // Fixed-point requantization
            scaled = (acc_ref + 256) >>> 9;

            // ReLU and saturation
            if (scaled < 0)
                reference_conv = 0;

            else if (scaled > 127)
                reference_conv = 127;

            else
                reference_conv = scaled[`CNN_ACT_WIDTH-1:0];
        end

    endfunction

    // =====================================================
    // FEATURE MAP OUTPUT MONITOR
    // =====================================================
    always @(posedge clk) begin

        if (fm_we) begin

            total_writes = total_writes + 1;
            image_writes = image_writes + 1;

            // Decode feature map address
            filter_index = fm_waddr / OUT_PER_FILTER;

            output_row =
                (fm_waddr % OUT_PER_FILTER) / OUT_WIDTH;

            output_col =
                (fm_waddr % OUT_PER_FILTER) % OUT_WIDTH;

            // Calculate expected result
            expected = reference_conv(
                img_base,
                filter_index,
                output_row,
                output_col
            );

            // Compare DUT and reference
            if (fm_wdata === expected) begin
                total_pass = total_pass + 1;
                image_pass = image_pass + 1;
            end
            else begin
                total_fail = total_fail + 1;
                image_fail = image_fail + 1;

                if (total_fail <= 20) begin
                    $display(
                        "FAIL | Image=%0d | Addr=%0d | Filter=%0d | Row=%0d | Col=%0d | DUT=%0d | REF=%0d",
                        image_index,
                        fm_waddr,
                        filter_index,
                        output_row,
                        output_col,
                        fm_wdata,
                        expected
                    );
                end
            end

        end
    end

    // =====================================================
    // MAIN TEST
    // =====================================================
    initial begin

        // Initialize signals
        clk = 0;
        rst = 1;
        start = 0;
        img_base = 0;
        img_data = 0;

        image_index = 0;

        total_pass = 0;
        total_fail = 0;
        total_writes = 0;

        image_pass = 0;
        image_fail = 0;
        image_writes = 0;

        // Load memory initialization files
        $display("----------------------------------------");
        $display("Loading memory files...");
        $readmemh("test_images.mem", image_mem);
        $readmemh("conv_weight.mem", weight_mem);
        $readmemh("conv_bias.mem", bias_mem);

        // Reset DUT
        repeat (5) @(negedge clk);
        rst = 0;

        // Run all images
        for (image_index = 0;
             image_index < NUM_IMAGES;
             image_index = image_index + 1) begin

            // Initialize per-image counters
            image_pass = 0;
            image_fail = 0;
            image_writes = 0;

            // Select image base address
            img_base = image_index * IMAGE_SIZE;

            $display("");
            $display("========================================");
            $display("START IMAGE %0d", image_index);
            $display("Image base address = %0d", img_base);
            $display("========================================");

            // Wait until DUT is idle
            wait(busy == 0);
            @(negedge clk);

            // Start pulse
            start = 1;
            @(negedge clk);
            start = 0;

            // Wait for completion
            wait(done == 1);

            // Allow final monitor updates
            @(negedge clk);

            // Per-image summary
            $display("----------------------------------------");
            $display("IMAGE %0d SUMMARY", image_index);
            $display("PASS   = %0d", image_pass);
            $display("FAIL   = %0d", image_fail);
            $display("WRITES = %0d", image_writes);
            $display("----------------------------------------");

            // Check expected number of outputs
            if (image_writes != TOTAL_OUTPUTS) begin
                $display(
                    "ERROR: Expected %0d writes, received %0d",
                    TOTAL_OUTPUTS,
                    image_writes
                );

                total_fail = total_fail + 1;
            end

        end

        // =================================================
        // FINAL SUMMARY
        // =================================================
        $display("");
        $display("========================================");
        $display("       DSP CONV ENGINE TEST SUMMARY");
        $display("========================================");

        $display("Number of images = %0d", NUM_IMAGES);
        $display("Filters          = %0d", NUM_FILTERS);
        $display("Output per image = %0d", TOTAL_OUTPUTS);
        $display("Expected writes  = %0d",
                 NUM_IMAGES * TOTAL_OUTPUTS);

        $display("----------------------------------------");
        $display("TOTAL PASS  = %0d", total_pass);
        $display("TOTAL FAIL  = %0d", total_fail);
        $display("TOTAL WRITES= %0d", total_writes);
        $display("----------------------------------------");

        if ((total_fail == 0) &&
            (total_writes == NUM_IMAGES * TOTAL_OUTPUTS)) begin

            $display("TEST PASSED");

        end
        else begin

            $display("TEST FAILED: %0d errors, %0d of %0d writes", total_fail, total_writes, NUM_IMAGES * TOTAL_OUTPUTS);

        end

        $display("========================================");

        $finish;

    end

    // =====================================================
    // WATCHDOG
    // =====================================================
    initial begin
        #200000000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule