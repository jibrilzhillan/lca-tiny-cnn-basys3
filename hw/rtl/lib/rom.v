// rom.v
// Generic synchronous ROM with parameterized initialization and ROM style.
`timescale 1ns/1ps

// INIT_FILE contains one hexadecimal word per line, loaded by $readmemh.
// Present addr before a rising clock edge; data updates after that edge.
module rom #(
    parameter integer DATA_WIDTH = 8,
    parameter integer ADDR_WIDTH = 8,
    parameter integer DEPTH = (1 << ADDR_WIDTH),
    parameter INIT_FILE = "",
    parameter ROM_STYLE = "auto"
) (
    input  wire                  clk,
    input  wire [ADDR_WIDTH-1:0] addr,
    output reg  [DATA_WIDTH-1:0] data
);

    (* rom_style = ROM_STYLE *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Pass a bare file name; Vivado Tcl adds the .mem file to the project.
    // Standalone simulators must place that file in their run directory.
    // Set INIT_FILE when instantiating an inference ROM. An empty path
    // leaves its contents unspecified; there is no implicit zero fill.
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    // One-cycle synchronous read, with no extra output pipeline stage.
    // The caller must keep addr within 0 .. DEPTH-1.
    always @(posedge clk) begin
        data <= mem[addr];
    end

    // Memory stores bit patterns. The consumer interprets signed weights
    // and biases with a signed signal or $signed(data).
endmodule
