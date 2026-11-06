// hex_to_7seg.v
// Hex digit (0-F) -> active-low seven-segment pattern, seg[6]=g ... seg[0]=a.

`timescale 1ns / 1ps

module hex_to_7seg(
    input [3:0] hex, // 4-bit number to display (0~F)
    output reg [6:0] seg // a~g control signals
);
    // Segment order: g, f, e, d, c, b, a (MSB → LSB)
    // Alternatively a~g order depending on mapping
    // Here we assume seg[6]=g ... seg[0]=a
    // Basys3 convention: seg[0]=a, seg[1]=b ... seg[6]=g
    always @(*) begin
    case(hex)
    // Segments that turn on for 0 (Common Anode)
    // Pattern: g f e d c b a
    4'h0: seg = 7'b1000000; // 0: only g is OFF(1)
    4'h1: seg = 7'b1111001; // 1: only b,c are ON(0)
    4'h2: seg = 7'b0100100; // 2
    4'h3: seg = 7'b0110000; // 3
    4'h4: seg = 7'b0011001; // 4
    4'h5: seg = 7'b0010010; // 5
    4'h6: seg = 7'b0000010; // 6
    4'h7: seg = 7'b1111000; // 7
    4'h8: seg = 7'b0000000; // 8 (all segments ON)
    4'h9: seg = 7'b0010000; // 9
    4'hA: seg = 7'b0001000; // A
    4'hB: seg = 7'b0000011; // b (lower case)
    4'hC: seg = 7'b1000110; // C
    4'hD: seg = 7'b0100001; // d (lower case)
    4'hE: seg = 7'b0000110; // E
    4'hF: seg = 7'b0001110; // F
    default: seg = 7'b1111111; // all segment OFF
    endcase
    end

endmodule
