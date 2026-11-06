// btn_debounce.v
// 2-FF synchronizer + ~10 ms debounce + rising-edge 1-cycle pulse.
//
// The button must hold a new value for STABLE cycles before btn_level follows it.
// Bounces shorter than that are ignored. btn_rise_p pulses for exactly 1 cycle when
// btn_level goes 0 -> 1 (one pulse per press).
//   BTNC: use btn_rise_p as the start pulse.
//   BTNU: use btn_level as the reset (held = reset).
// No reset input on purpose: the reset button itself goes through this module.
// Registers start at 0 from the bitstream (FPGA power-up values).
//   SIM = 0: STABLE = 1,000,000 cycles = 10 ms at 100 MHz
//   SIM = 1: STABLE = 16 cycles, for testbenches

`timescale 1ns / 1ps

module btn_debounce #(
    parameter SIM = 0
) (
    input  wire clk,
    input  wire btn_in,       // raw button pin, asynchronous
    output reg  btn_level,    // debounced level
    output reg  btn_rise_p    // 1-cycle pulse on each press
);

    localparam STABLE = SIM ? 16 : 1000000;
    localparam CNT_W  = $clog2(STABLE);

    // 2-FF synchronizer: brings the asynchronous pin into the clk domain
    (* ASYNC_REG = "TRUE" *) reg sync_0 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg sync_1 = 1'b0;
    always @(posedge clk) begin
        sync_0 <= btn_in;
        sync_1 <= sync_0;
    end

    // Count how long the synchronized input has differed from btn_level
    reg [CNT_W-1:0] cnt = {CNT_W{1'b0}};
    initial begin
        btn_level  = 1'b0;
        btn_rise_p = 1'b0;
    end

    always @(posedge clk) begin
        btn_rise_p <= 1'b0;
        if (sync_1 == btn_level) begin
            cnt <= {CNT_W{1'b0}};
        end else if (cnt == STABLE - 1) begin
            cnt        <= {CNT_W{1'b0}};
            btn_level  <= sync_1;
            btn_rise_p <= sync_1;          // pulse only on 0 -> 1
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

endmodule
