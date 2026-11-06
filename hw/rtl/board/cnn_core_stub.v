// cnn_core_stub.v
// Stand-in for cnn_core with the same ports, for board-side tests (top_basys3 USE_STUB = 1).
//
// busy for RUN_CYCLES (as long as a real inference), then a 1-cycle done with
// class_id = image % 3 and cycle_count = RUN_CYCLES. start is ignored while busy.

`timescale 1ns / 1ps

module cnn_core_stub #(
    parameter RUN_CYCLES = 106042
) (
    input  wire               clk,
    input  wire               rst,           // synchronous, active high
    input  wire [3:0]         img_sel,       // latched on start
    input  wire               start,         // 1-cycle pulse
    output reg                done,          // 1-cycle pulse
    output reg                busy,
    output reg  [1:0]         class_id,      // held until the next run
    output wire signed [31:0] logit0,
    output wire signed [31:0] logit1,
    output wire signed [31:0] logit2,
    output reg  [19:0]        cycle_count
);

    reg [3:0]  img_q;
    reg [19:0] cnt;

    assign logit0 = 32'sd0;
    assign logit1 = 32'sd0;
    assign logit2 = 32'sd0;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            busy        <= 1'b0;
            class_id    <= 2'd0;
            cycle_count <= 20'd0;
            img_q       <= 4'd0;
            cnt         <= 20'd0;
        end else if (busy) begin
            cnt <= cnt + 1'b1;
            if (cnt == RUN_CYCLES - 1) begin
                busy        <= 1'b0;
                done        <= 1'b1;
                class_id    <= img_q % 3;
                cycle_count <= RUN_CYCLES;
            end
        end else if (start) begin
            busy  <= 1'b1;
            cnt   <= 20'd0;
            img_q <= img_sel;
        end
    end

endmodule
