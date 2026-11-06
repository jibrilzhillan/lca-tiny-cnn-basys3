// ram.v
// Generic one-read/one-write synchronous RAM with selectable style/init.
`timescale 1ns/1ps

// Writes and registered reads occur on the rising edge of clk.
// A simultaneous read/write of the same address returns the OLD value.
module ram #(
    parameter integer DATA_WIDTH = 8,
    parameter integer ADDR_WIDTH = 8,
    parameter integer DEPTH = (1 << ADDR_WIDTH),
    parameter INIT_FILE = "",
    parameter RAM_STYLE = "block"
) (
    input  wire                  clk,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] waddr,
    input  wire [DATA_WIDTH-1:0] wdata,
    input  wire [ADDR_WIDTH-1:0] raddr,
    output reg  [DATA_WIDTH-1:0] rdata
);

    (* ram_style = RAM_STYLE *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Optional initialization, using a bare file name added by Vivado Tcl.
    // An empty INIT_FILE leaves storage unspecified until written.
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    // One-cycle read, independent of the write port. Nonblocking
    // assignments give read-first behavior on a same-address collision.
    // The caller must keep both addresses within 0 .. DEPTH-1.
    always @(posedge clk) begin
        if (we) begin
            mem[waddr] <= wdata;
        end
        rdata <= mem[raddr];
    end

    // No reset or automatic zero-fill of the storage array. Without an
    // INIT_FILE, read a location only after the producing engine has
    // written it; rdata is unspecified until a valid clocked read.
endmodule
