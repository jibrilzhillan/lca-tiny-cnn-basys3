// top_basys3.v
// Board top: btn_debounce x2, cnn_core, label_rom, result_display, seg7_mux.
//
// Port names match hw/constr/basys3.xdc. Board I/O as in the board controls table in README.md.
//   SIM = 1:      short debounce and fast display scan, for testbenches
//   USE_STUB = 1: cnn_core_stub replaces cnn_core and a small table replaces label_rom, so the
//                 board side can be tested without the CNN or the .mem files
// The label address is latched on an accepted start, so PASS/FAIL compares against the image
// that actually ran even if the switches move during the run.

`timescale 1ns / 1ps

module top_basys3 #(
    parameter SIM      = 0,
    parameter USE_STUB = 0
) (
    input  wire        clk,           // W5, 100 MHz
    input  wire [15:0] sw,            // SW[3:0] image, SW[14] display mode, SW[15] reserved
    input  wire        btnC,          // start
    input  wire        btnU,          // reset
    output wire [15:0] led,
    output wire [6:0]  seg,           // active low, seg[0] = a
    output wire        dp,            // active low
    output wire [3:0]  an             // active low, an[0] = rightmost
);

    // Reset: BTNU held, plus the first 15 cycles after configuration
    wire btnU_level;
    btn_debounce #(.SIM(SIM)) u_deb_rst (
        .clk(clk), .btn_in(btnU), .btn_level(btnU_level), .btn_rise_p()
    );

    reg [3:0] por_cnt = 4'd0;
    wire      por     = (por_cnt != 4'hF);
    always @(posedge clk) begin
        if (por) por_cnt <= por_cnt + 1'b1;
    end

    wire rst = por | btnU_level;

    // Start: one pulse per press
    wire start_p;
    btn_debounce #(.SIM(SIM)) u_deb_start (
        .clk(clk), .btn_in(btnC), .btn_level(), .btn_rise_p(start_p)
    );

    // 2-FF synchronizer for the switches in use
    (* ASYNC_REG = "TRUE" *) reg [5:0] sw_sync_0 = 6'd0;
    (* ASYNC_REG = "TRUE" *) reg [5:0] sw_sync_1 = 6'd0;
    always @(posedge clk) begin
        sw_sync_0 <= {sw[14], sw[13], sw[3:0]};
        sw_sync_1 <= sw_sync_0;
    end

    wire       mode    = sw_sync_1[5];
    wire       cyc_hi  = sw_sync_1[4];
    wire [3:0] img_sel = sw_sync_1[3:0];

    // Accelerator
    wire [1:0]  class_id;
    wire        done_p;
    wire        busy;
    wire [19:0] cycle_count;

    generate
        if (USE_STUB) begin : gen_stub
            cnn_core_stub u_core (
                .clk(clk), .rst(rst), .img_sel(img_sel), .start(start_p),
                .done(done_p), .busy(busy), .class_id(class_id),
                .logit0(), .logit1(), .logit2(), .cycle_count(cycle_count)
            );
        end else begin : gen_core
            cnn_core u_core (
                .clk(clk), .rst(rst), .img_sel(img_sel), .start(start_p),
                .done(done_p), .busy(busy), .class_id(class_id),
                .logit0(), .logit1(), .logit2(), .cycle_count(cycle_count)
            );
        end
    endgenerate

    // Expected label of the image that ran
    reg [3:0] label_addr = 4'd0;
    always @(posedge clk) begin
        if (rst)
            label_addr <= 4'd0;
        else if (start_p && !busy && !done_p)
            label_addr <= img_sel;
    end

    wire [1:0] label;
    generate
        if (USE_STUB) begin : gen_stub_label
            // Same as the stub's class, except image 15, so FAIL can be seen too
            assign label = (label_addr == 4'd15) ? 2'd1 : label_addr % 3;
        end else begin : gen_label_rom
            // Generic synchronous ROM; the label follows the accepted START.
            rom #(.DATA_WIDTH(2), .ADDR_WIDTH(4), .DEPTH(16), .INIT_FILE("test_labels.mem"), .ROM_STYLE("distributed"))
                label_rom (.clk(clk), .addr(label_addr), .data(label));
        end
    endgenerate

    // Display
    wire [6:0] digit0_n, digit1_n, digit2_n, digit3_n;
    wire [3:0] dp_n;

    result_display u_disp (
        .clk(clk), .rst(rst),
        .class_id(class_id), .done_p(done_p), .busy(busy),
        .label(label), .img_sel(img_sel),
        .cycle_count(cycle_count), .mode(mode), .cyc_hi(cyc_hi),
        .led(led),
        .digit0_n(digit0_n), .digit1_n(digit1_n), .digit2_n(digit2_n), .digit3_n(digit3_n),
        .dp_n(dp_n)
    );

    seg7_mux #(.SIM(SIM)) u_mux (
        .clk(clk), .rst(rst),
        .digit0_n(digit0_n), .digit1_n(digit1_n), .digit2_n(digit2_n), .digit3_n(digit3_n),
        .dp_in_n(dp_n),
        .seg_n(seg), .dp_n(dp), .an_n(an)
    );

endmodule
