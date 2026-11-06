// result_display.v
// Class -> LED position bar (where the car is in its lane), LF/St/rt, PASS/FAIL, SW[14] display mode.
//
// Board outputs (see the board controls table in README.md):
//   LED[15:13] LEFT, LED[8:7] STRAIGHT, LED[2:0] RIGHT   position bar (after the first run)
//   LED[11] PASS, LED[10] FAIL                            result vs the stored expected label
//   LED[4] DONE (a result is shown), LED[3] BUSY
//   mode = 0: digit 3 = image index (hex), digit 2 blank, digits 1-0 = LF / St / rt ("--" before the first run)
//   mode = 1: digits 3-0 = cycle_count in hex
// The class and PASS/FAIL are captured on done_p, so moving the switches afterwards
// doesn't change the shown result. Digit outputs go to seg7_mux.

`timescale 1ns / 1ps

module result_display (
    input  wire        clk,
    input  wire        rst,           // synchronous, active high
    input  wire [1:0]  class_id,      // from cnn_core: 0 LEFT, 1 STRAIGHT, 2 RIGHT
    input  wire        done_p,        // from cnn_core: 1-cycle pulse, class_id valid
    input  wire        busy,          // from cnn_core
    input  wire [1:0]  label,         // expected class of the selected image (label_rom)
    input  wire [3:0]  img_sel,       // SW[3:0]
    input  wire [19:0] cycle_count,   // from cnn_core
    input  wire        cyc_hi,        // SW[13]: upper cycle-count page
    input  wire        mode,          // SW[14]: 0 = result, 1 = latency
    output reg  [15:0] led,
    output wire [6:0]  digit0_n,      // to seg7_mux, active low, bit 6 = g ... bit 0 = a
    output wire [6:0]  digit1_n,
    output wire [6:0]  digit2_n,
    output wire [6:0]  digit3_n,
    output wire [3:0]  dp_n
);

    // Letters, active low, pattern g f e d c b a
    localparam [6:0] CH_L     = 7'b1000111;
    localparam [6:0] CH_F     = 7'b0001110;
    localparam [6:0] CH_S     = 7'b0010010;
    localparam [6:0] CH_t     = 7'b0000111;
    localparam [6:0] CH_r     = 7'b0101111;
    localparam [6:0] CH_DASH  = 7'b0111111;
    localparam [6:0] CH_BLANK = 7'b1111111;

    // Result captured at the end of each run
    reg       have_result;
    reg [1:0] res_class;
    reg       res_pass;

    always @(posedge clk) begin
        if (rst) begin
            have_result <= 1'b0;
            res_class   <= 2'd0;
            res_pass    <= 1'b0;
        end else if (done_p) begin
            have_result <= 1'b1;
            res_class   <= class_id;
            res_pass    <= (class_id == label);
        end
    end

    // LEDs
    always @(posedge clk) begin
        if (rst) begin
            led <= 16'h0000;
        end else begin
            led <= 16'h0000;
            if (have_result) begin
                case (res_class)
                    2'd0:    led[15:13] <= 3'b111;
                    2'd1:    led[8:7]   <= 2'b11;
                    2'd2:    led[2:0]   <= 3'b111;
                    default: ;
                endcase
                led[11] <= res_pass;
                led[10] <= ~res_pass;
                led[4]  <= 1'b1;
            end
            led[3] <= busy;
        end
    end

    // Hex digits (image index or cycle count)
    wire [15:0] shown_count=cyc_hi?{12'd0,cycle_count[19:16]}:cycle_count[15:0];
    wire [6:0] hex3_n, hex2_n, hex1_n, hex0_n;
    hex_to_7seg u_hex3 (.hex(mode ? shown_count[15:12] : img_sel), .seg(hex3_n));
    hex_to_7seg u_hex2 (.hex(shown_count[11:8]),                   .seg(hex2_n));
    hex_to_7seg u_hex1 (.hex(shown_count[7:4]),                    .seg(hex1_n));
    hex_to_7seg u_hex0 (.hex(shown_count[3:0]),                    .seg(hex0_n));

    // Result characters
    reg [6:0] res1_n, res0_n;
    always @(*) begin
        if (!have_result) begin
            res1_n = CH_DASH;  res0_n = CH_DASH;
        end else begin
            case (res_class)
                2'd0:    begin res1_n = CH_L;    res0_n = CH_F;    end
                2'd1:    begin res1_n = CH_S;    res0_n = CH_t;    end
                2'd2:    begin res1_n = CH_r;    res0_n = CH_t;    end
                default: begin res1_n = CH_DASH; res0_n = CH_DASH; end
            endcase
        end
    end

    assign digit3_n = hex3_n;
    assign digit2_n = mode ? hex2_n : CH_BLANK;
    assign digit1_n = mode ? hex1_n : res1_n;
    assign digit0_n = mode ? hex0_n : res0_n;
    assign dp_n     = 4'b1111;

endmodule
