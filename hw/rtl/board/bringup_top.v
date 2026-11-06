// bringup_top.v
// H0 board bring-up: LEDs follow the switches, rightmost 7-seg digit shows SW[3:0] in hex.
//
// Kept after H0 as a known-good board test: if the real design misbehaves on the board,
// rebuild this to tell a board/pin problem from a design problem.
//   SW[15:0]  -> LED[15:0]
//   SW[3:0]   -> digit 0 (rightmost), hex 0-F
//   dp        -> blinks at ~1.5 Hz (proves the 100 MHz clock is running)
//   BTNC held -> lamp test: all segments and all 4 digits on ("8.8.8.8.")
//   BTNU held -> all 16 LEDs on

module bringup_top (
    input  wire        clk,
    input  wire [15:0] sw,
    input  wire        btnC,
    input  wire        btnU,
    output wire [15:0] led,
    output wire [6:0]  seg,   // active low, seg[0] = a ... seg[6] = g
    output wire        dp,    // active low
    output wire [3:0]  an     // active low, an[0] = rightmost digit
);

    // Heartbeat: bit 25 of a free-running counter toggles every 2^25 cycles (~0.34 s at 100 MHz)
    reg [25:0] hb_cnt = 26'd0;
    always @(posedge clk)
        hb_cnt <= hb_cnt + 26'd1;

    // Hex digit -> segments, active high here (bit order g f e d c b a), inverted at the output
    reg [6:0] seg_on;
    always @(*) begin
        case (sw[3:0])
            4'h0: seg_on = 7'b0111111;
            4'h1: seg_on = 7'b0000110;
            4'h2: seg_on = 7'b1011011;
            4'h3: seg_on = 7'b1001111;
            4'h4: seg_on = 7'b1100110;
            4'h5: seg_on = 7'b1101101;
            4'h6: seg_on = 7'b1111101;
            4'h7: seg_on = 7'b0000111;
            4'h8: seg_on = 7'b1111111;
            4'h9: seg_on = 7'b1101111;
            4'hA: seg_on = 7'b1110111;
            4'hB: seg_on = 7'b1111100;  // b
            4'hC: seg_on = 7'b0111001;
            4'hD: seg_on = 7'b1011110;  // d
            4'hE: seg_on = 7'b1111001;
            4'hF: seg_on = 7'b1110001;
            default: seg_on = 7'b0000000;
        endcase
    end

    assign led = btnU ? 16'hFFFF : sw;
    assign seg = btnC ? 7'b0000000 : ~seg_on;
    assign dp  = btnC ? 1'b0 : ~hb_cnt[25];
    assign an  = btnC ? 4'b0000 : 4'b1110;

endmodule
