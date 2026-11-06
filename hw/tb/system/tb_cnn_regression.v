// tb_cnn_regression.v
// R1: run the real cnn_core on many test images and compare every result
// with the Python integer golden model (hw/tools/int_model.py).
`timescale 1ns/1ps
`include "cnn_params.vh"
// Number of images: run_regression.py writes reg_config.vh
// (`define REG_NUM_IMAGES N, a multiple of 16) next to the vectors and
// defines REG_USE_CONFIG. The count is not passed as -d NAME=VALUE because
// Windows .bat wrappers (xvlog.bat) split arguments at '='.
// Without REG_USE_CONFIG (e.g. in the Vivado project) N defaults to 128.
`ifdef REG_USE_CONFIG
`include "reg_config.vh"
`endif
`ifndef REG_NUM_IMAGES
`define REG_NUM_IMAGES 128
`endif

// Vectors come from hw/tools/gen_regression_vectors.py. The image ROM holds
// 16 images, so the testbench loads the next 16 into dut.image_rom.mem
// between batches (simulation only; the board build is unchanged).
// For each image it checks the three logits, the class and the cycle count,
// and writes one CSV line to reg_results.csv.
module tb_cnn_regression;
    localparam integer N = `REG_NUM_IMAGES;
    localparam integer PIX = `CNN_IMG_PIXELS;
    localparam integer BATCH = `CNN_NUM_IMAGES;

    reg clk = 0, rst = 1, start = 0;
    always #5 clk = ~clk;
    reg [3:0] image_sel = 0;
    wire busy, done;
    wire [1:0] cls;
    wire signed [31:0] l0, l1, l2;
    wire [`CNN_CYCLE_WIDTH-1:0] count;

    reg [7:0]  images  [0:N*PIX-1];
    reg [31:0] expected[0:N*4-1];
    reg [3:0]  labels  [0:N-1];

    integer errors = 0, mismatches = 0, hw_correct = 0, py_correct = 0;
    integer k, b, i, cycles, fd, img_errors;
    integer cm[0:8];  // confusion matrix of the hardware: cm[label*3 + class]
    `include "tb_utils.vh"

    cnn_core dut(.clk(clk), .rst(rst), .start(start), .img_sel(image_sel), .busy(busy), .done(done),
        .class_id(cls), .logit0(l0), .logit1(l1), .logit2(l2), .cycle_count(count));

    task run_one;
        input integer slot;   // 0..15, position in the image ROM
        input integer k;      // global image index
        begin
            @(negedge clk); image_sel = slot; start = 1;
            @(negedge clk); start = 0; cycles = 0;
            while (!done && cycles < `CNN_TARGET_CYCLES + 1) begin @(negedge clk); cycles = cycles + 1; end
            img_errors = errors;
            check(done && !busy, "core timeout");
            check(count == cycles && count <= `CNN_TARGET_CYCLES, "cycle count/target mismatch");
            compare_word(l0, expected[k*4],   k, "logit0");
            compare_word(l1, expected[k*4+1], k, "logit1");
            compare_word(l2, expected[k*4+2], k, "logit2");
            compare_word({30'b0, cls}, expected[k*4+3], k, "class");
            if (errors != img_errors) mismatches = mismatches + 1;
            if (cls == labels[k]) hw_correct = hw_correct + 1;
            if (expected[k*4+3] == labels[k]) py_correct = py_correct + 1;
            cm[labels[k]*3 + cls] = cm[labels[k]*3 + cls] + 1;
            $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,", k, labels[k],
                expected[k*4+3], cls, $signed(expected[k*4]), $signed(expected[k*4+1]), $signed(expected[k*4+2]),
                l0, l1, l2, count, errors == img_errors);
            if (errors == img_errors) $fwrite(fd, "MATCH\n"); else $fwrite(fd, "MISMATCH\n");
            @(negedge clk);
        end
    endtask

    initial begin
        $readmemh("reg_images.mem", images);
        $readmemh("reg_expected.mem", expected);
        $readmemh("reg_labels.mem", labels);
        for (i = 0; i < 9; i = i + 1) cm[i] = 0;
        check((^expected[N*4-1]) !== 1'bx, "reg_expected.mem is shorter than REG_NUM_IMAGES");
        check((^images[N*PIX-1]) !== 1'bx, "reg_images.mem is shorter than REG_NUM_IMAGES");
        fd = $fopen("reg_results.csv", "w");
        $fwrite(fd, "index,label,py_class,hw_class,py_logit0,py_logit1,py_logit2,hw_logit0,hw_logit1,hw_logit2,cycles,match,status\n");
        repeat (2) @(negedge clk); rst = 0;
        for (b = 0; b < N / BATCH; b = b + 1) begin
            // Load the next 16 images into the image ROM while the core is idle.
            for (i = 0; i < BATCH*PIX; i = i + 1) dut.image_rom.mem[i] = images[b*BATCH*PIX + i];
            for (k = 0; k < BATCH; k = k + 1) run_one(k, b*BATCH + k);
            $display("batch %0d/%0d done: %0d images, %0d mismatches so far", b + 1, N / BATCH, (b + 1)*BATCH, mismatches);
        end
        $fclose(fd);
        $display("REGRESSION: %0d images, FPGA vs Python model agree on %0d/%0d (%0d mismatches)",
            N, N - mismatches, N, mismatches);
        $display("REGRESSION: accuracy vs true label: FPGA %0d/%0d, Python %0d/%0d", hw_correct, N, py_correct, N);
        $display("REGRESSION: FPGA confusion matrix (rows = label L/S/R, cols = predicted L/S/R)");
        for (i = 0; i < 3; i = i + 1) $display("  %5d %5d %5d", cm[i*3], cm[i*3+1], cm[i*3+2]);
        report_test;
        $finish;
    end
endmodule
