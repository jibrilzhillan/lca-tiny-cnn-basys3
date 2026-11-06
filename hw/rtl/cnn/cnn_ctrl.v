// cnn_ctrl.v
// Sequence CONV/POOL/FC/ARGMAX with image latching and cycle measurement.
`timescale 1ns/1ps
`include "cnn_params.vh"

// CNN stage sequencer. Synchronous, active-high reset; Verilog-2001.
// Engine start/done signals are one-clock pulses on this clock domain.
module cnn_ctrl (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [`CNN_IMG_SEL_WIDTH-1:0] img_sel,
    input  wire        conv_done,
    input  wire        pool_done,
    input  wire        fc_done,

    output reg         conv_start,
    output reg         pool_start,
    output reg         fc_start,
    output reg         argmax_start,
    output wire        busy,
    output wire        done,
    output reg [`CNN_IMG_SEL_WIDTH-1:0] img_sel_q,
    output reg [`CNN_CYCLE_WIDTH-1:0] cycle_count
);

    localparam [2:0] ST_IDLE   = 3'd0,
                     ST_CONV   = 3'd1,
                     ST_POOL   = 3'd2,
                     ST_FC     = 3'd3,
                     ST_ARGMAX = 3'd4,
                     ST_DONE   = 3'd5;

    reg [2:0] state_q;

    assign busy = (state_q == ST_CONV) || (state_q == ST_POOL) ||
                  (state_q == ST_FC)   || (state_q == ST_ARGMAX);
    assign done = (state_q == ST_DONE);

    always @(posedge clk) begin
        if (rst) begin
            state_q      <= ST_IDLE;
            conv_start   <= 1'b0;
            pool_start   <= 1'b0;
            fc_start     <= 1'b0;
            argmax_start <= 1'b0;
            img_sel_q    <= {`CNN_IMG_SEL_WIDTH{1'b0}};
            cycle_count  <= {`CNN_CYCLE_WIDTH{1'b0}};
        end else begin
            // Default low makes every stage launch a one-clock pulse.
            conv_start   <= 1'b0;
            pool_start   <= 1'b0;
            fc_start     <= 1'b0;
            argmax_start <= 1'b0;

            // Zero at the accepted START edge. At DONE this is the
            // elapsed number of clocks since that edge, including the
            // argmax capture edge. Hold the result until reset/new START.
            // D19/D20: target <=120000 clocks, with a 20-bit counter.
            // Counter wraps at 1048576; this is not an engine watchdog.
            if (busy) begin
                cycle_count <= cycle_count + 1'b1;
            end

            case (state_q)
                ST_IDLE: begin
                    if (start) begin
                        img_sel_q   <= img_sel;
                        cycle_count <= {`CNN_CYCLE_WIDTH{1'b0}};
                        conv_start  <= 1'b1;
                        state_q     <= ST_CONV;
                    end
                end

                ST_CONV: begin
                    if (conv_done) begin
                        pool_start <= 1'b1;
                        state_q    <= ST_POOL;
                    end
                end

                ST_POOL: begin
                    if (pool_done) begin
                        fc_start <= 1'b1;
                        state_q  <= ST_FC;
                    end
                end

                ST_FC: begin
                    if (fc_done) begin
                        argmax_start <= 1'b1;
                        state_q      <= ST_ARGMAX;
                    end
                end

                ST_ARGMAX: begin
                    // argmax_start was high before this edge: the
                    // datapath captures the class now. DONE goes high
                    // after the edge, when the registered class is valid.
                    state_q <= ST_DONE;
                end

                ST_DONE: begin
                    state_q <= ST_IDLE;
                end

                default: begin
                    state_q     <= ST_IDLE;
                    cycle_count <= {`CNN_CYCLE_WIDTH{1'b0}};
                end
            endcase
        end
    end

    // START is accepted only in IDLE. Pulses while busy or during DONE
    // are discarded, not queued. Launch again after DONE returns low.
    // Reset must also reach the engines so that an aborted run cannot
    // leave stale engine completion pulses in a subsequent inference.
endmodule
