// conv_engine.v
// 3x3 conv, 4 filters, address generator. Instantiates conv_w_rom, conv_b_rom, mac, relu_requant.

`timescale 1ns/1ps
`include "cnn_params.vh"

module conv_engine #(
    parameter WEIGHT_FILE = "conv_weight.mem",
    parameter BIAS_FILE   = "conv_bias.mem",
    parameter integer S1 = 9
) (
    input  wire clk,
    input  wire rst,
    input  wire start,

    output reg  done,
    output wire busy,

    input  wire [`CNN_IMAGE_ADDR_WIDTH-1:0] img_base,
    output wire [`CNN_IMAGE_ADDR_WIDTH-1:0] img_addr,
    input  wire [`CNN_PIXEL_WIDTH-1:0] img_data,

    output wire [`CNN_FMAP_ADDR_WIDTH-1:0] fm_waddr,
    output wire [`CNN_ACT_WIDTH-1:0] fm_wdata,
    output wire fm_we
);

    // ---------------------------------------------------------
    // FSM STATE DEFINITIONS
    // ---------------------------------------------------------
    localparam [2:0]
        ST_IDLE      = 3'd0,
        ST_BIAS_WAIT = 3'd1,
        ST_BIAS_LOAD = 3'd2,
        ST_ISSUE     = 3'd3,
        ST_DRAIN     = 3'd4,
        ST_WRITE     = 3'd5;

    reg [2:0] state;

    // Current filter, output coordinates, and kernel index.
    reg [1:0] filter_q;
    reg [4:0] oy;
    reg [5:0] ox;
    reg [3:0] k;

    assign busy = (state != ST_IDLE);


    // ---------------------------------------------------------
    // WEIGHT ROM AND BIAS ROM
    // ---------------------------------------------------------
    wire [5:0] weight_addr;
    wire [7:0] weight_data;
    wire [31:0] bias_data;

    assign weight_addr = (filter_q * 6'd9) + k;

    rom #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(6),
        .DEPTH(36),
        .INIT_FILE(WEIGHT_FILE),
        .ROM_STYLE("distributed")
    ) weight_rom (
        .clk(clk),
        .addr(weight_addr),
        .data(weight_data)
    );

    rom #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(2),
        .DEPTH(4),
        .INIT_FILE(BIAS_FILE),
        .ROM_STYLE("distributed")
    ) bias_rom (
        .clk(clk),
        .addr(filter_q),
        .data(bias_data)
    );


    // ---------------------------------------------------------
    // IMAGE ADDRESS GENERATOR
    // ---------------------------------------------------------
    address_generator u_address_generator (
        .img_base(img_base),
        .oy(oy),
        .ox(ox),
        .k(k),
        .img_addr(img_addr)
    );


    // ---------------------------------------------------------
    // DSP48 MULTIPLY-ACCUMULATE
    // ---------------------------------------------------------
    // Pixel is unsigned 8-bit.
    // Weight is signed 8-bit.
    // Both are connected directly to the DSP MAC module.

    reg valid_d;

    wire acc_load;
    wire acc_enable;

    wire signed [23:0] acc;

    assign acc_load   = (state == ST_BIAS_LOAD);
    assign acc_enable = valid_d;

    mac u_mac (
        .clk(clk),
        .rst(rst),

        .acc_clear(1'b0),
        .acc_load(acc_load),
        .acc_enable(acc_enable),

        .pixel(img_data),
        .weight($signed(weight_data)),

        .acc_load_data(bias_data[23:0]),
        .acc(acc)
    );


    // ---------------------------------------------------------
    // RELU AND REQUANTIZATION
    // ---------------------------------------------------------
    wire [6:0] activation;

    relu_requant #(
        .S1(S1)
    ) u_relu_requant (
        .acc(acc),
        .activation(activation)
    );


    // ---------------------------------------------------------
    // FEATURE MAP OUTPUT
    // ---------------------------------------------------------
    wire [12:0] fmap_address;

    assign fmap_address =
        (filter_q * 13'd1860) +
        (oy * 13'd62) +
        ox;

    assign fm_waddr = fmap_address;

    assign fm_wdata =
        {{(`CNN_ACT_WIDTH-7){1'b0}}, activation};

    assign fm_we = (state == ST_WRITE);


    // ---------------------------------------------------------
    // SEQUENTIAL CONTROLLER
    // ---------------------------------------------------------
    always @(posedge clk) begin

        if (rst) begin
            state    <= ST_IDLE;
            filter_q <= 0;
            oy       <= 0;
            ox       <= 0;
            k        <= 0;
            valid_d  <= 0;
            done     <= 0;
        end

        else begin

            done <= 0;

            // Delay valid signal to match synchronous ROM data.
            valid_d <= (state == ST_ISSUE);

            case (state)

                // Wait for a new convolution request.
                ST_IDLE: begin
                    valid_d <= 0;

                    if (start) begin
                        filter_q <= 0;
                        oy       <= 0;
                        ox       <= 0;
                        k        <= 0;

                        state <= ST_BIAS_WAIT;
                    end
                end


                // Wait for bias ROM output.
                ST_BIAS_WAIT: begin
                    state <= ST_BIAS_LOAD;
                end


                // Load bias into accumulator.
                ST_BIAS_LOAD: begin
                    k     <= 0;
                    state <= ST_ISSUE;
                end


                // Process nine pixels in the 3x3 kernel.
                ST_ISSUE: begin

                    if (k == 4'd8) begin
                        state <= ST_DRAIN;
                    end

                    else begin
                        k <= k + 1'b1;
                    end

                end


                // Allow final MAC operation to complete.
                ST_DRAIN: begin
                    valid_d <= 0;
                    state   <= ST_WRITE;
                end


                // Write activation to feature map.
                ST_WRITE: begin

                    if (ox < 6'd61) begin

                        ox    <= ox + 1'b1;
                        state <= ST_BIAS_WAIT;

                    end

                    else if (oy < 5'd29) begin

                        ox    <= 0;
                        oy    <= oy + 1'b1;
                        state <= ST_BIAS_WAIT;

                    end

                    else if (filter_q < 2'd3) begin

                        ox       <= 0;
                        oy       <= 0;
                        filter_q <= filter_q + 1'b1;

                        state <= ST_BIAS_WAIT;

                    end

                    else begin

                        state <= ST_IDLE;
                        done  <= 1;

                    end

                end


                // Return to idle if undefined state occurs.
                default: begin
                    state   <= ST_IDLE;
                    valid_d <= 0;
                end

            endcase
        end
    end

endmodule