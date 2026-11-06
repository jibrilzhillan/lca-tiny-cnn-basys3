// seg7_mux.v
// 4-digit multiplexed seven-segment driver, active-low.
//
// Lights one digit at a time, fast enough to look steady. It only scans: what each digit
// shows is decided by result_display (hex digits via hex_to_7seg, letters as constants).
//   Digit inputs:  active-low segment patterns, bit 6 = g ... bit 0 = a (same as hex_to_7seg)
//   Scan order:    digit 0 (rightmost, an[0]) -> 1 -> 2 -> 3 -> 0 ...
//   Digit period:  2^17 cycles = 1.31 ms at 100 MHz (each digit refreshed at ~190 Hz)
//   SIM = 1:       2^2 cycles per digit, so a testbench sees many scans quickly

`timescale 1ns / 1ps

module seg7_mux #(
    parameter SIM = 0
) (
    input  wire       clk,
    input  wire       rst,        // synchronous, active high
    input  wire [6:0] digit0_n,   // rightmost digit
    input  wire [6:0] digit1_n,
    input  wire [6:0] digit2_n,
    input  wire [6:0] digit3_n,   // leftmost digit
    input  wire [3:0] dp_in_n,    // decimal point per digit, dp_in_n[0] = rightmost
    output reg  [6:0] seg_n,      // to the seg pins
    output reg        dp_n,       // to the dp pin
    output reg  [3:0] an_n        // to the an pins, an_n[0] = rightmost
);

    localparam DIV_W = SIM ? 2 : 17;  // cycles per digit = 2^DIV_W

    reg [DIV_W+1:0] scan_cnt;         // top 2 bits select the digit
    wire [1:0] sel = scan_cnt[DIV_W+1:DIV_W];

    always @(posedge clk) begin
        if (rst)
            scan_cnt <= {(DIV_W+2){1'b0}};
        else
            scan_cnt <= scan_cnt + 1'b1;
    end

    // Registered outputs: segments and anode change on the same edge, no glitches on the pins
    always @(posedge clk) begin
        if (rst) begin
            seg_n <= 7'b1111111;
            dp_n  <= 1'b1;
            an_n  <= 4'b1111;
        end else begin
            case (sel)
                2'd0: begin seg_n <= digit0_n; dp_n <= dp_in_n[0]; an_n <= 4'b1110; end
                2'd1: begin seg_n <= digit1_n; dp_n <= dp_in_n[1]; an_n <= 4'b1101; end
                2'd2: begin seg_n <= digit2_n; dp_n <= dp_in_n[2]; an_n <= 4'b1011; end
                default: begin seg_n <= digit3_n; dp_n <= dp_in_n[3]; an_n <= 4'b0111; end
            endcase
        end
    end

endmodule
