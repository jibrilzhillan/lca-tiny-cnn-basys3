// cnn_params.vh
// Shared architecture sizes/widths; numerical shifts come from the model export.
`ifndef CNN_PARAMS_VH
`define CNN_PARAMS_VH

// 64x32 input (D16, D17).
// Shapes use C x H x W; image dimensions below are named explicitly.
`define CNN_IMG_WIDTH         64
`define CNN_IMG_HEIGHT        32
`define CNN_IMG_CHANNELS       1
`define CNN_NUM_IMAGES        16
`define CNN_IMG_SEL_WIDTH      4
`define CNN_IMG_PIXELS        (`CNN_IMG_WIDTH * `CNN_IMG_HEIGHT)
`define CNN_IMAGE_ROM_DEPTH   (`CNN_NUM_IMAGES * `CNN_IMG_PIXELS)

`define CNN_CONV_KERNEL        3
`define CNN_CONV_FILTERS       4
`define CNN_CONV_OUT_WIDTH    (`CNN_IMG_WIDTH - `CNN_CONV_KERNEL + 1)
`define CNN_CONV_OUT_HEIGHT   (`CNN_IMG_HEIGHT - `CNN_CONV_KERNEL + 1)
`define CNN_FMAP_PLANE_SIZE   (`CNN_CONV_OUT_WIDTH * `CNN_CONV_OUT_HEIGHT)
`define CNN_FMAP_DEPTH        (`CNN_CONV_FILTERS * `CNN_FMAP_PLANE_SIZE)
`define CNN_CONV_W_DEPTH      (`CNN_CONV_FILTERS * `CNN_IMG_CHANNELS * `CNN_CONV_KERNEL * `CNN_CONV_KERNEL)
`define CNN_CONV_B_DEPTH      `CNN_CONV_FILTERS

`define CNN_POOL_SIZE          2
`define CNN_POOL_OUT_WIDTH    (`CNN_CONV_OUT_WIDTH / `CNN_POOL_SIZE)
`define CNN_POOL_OUT_HEIGHT   (`CNN_CONV_OUT_HEIGHT / `CNN_POOL_SIZE)
`define CNN_POOL_PLANE_SIZE   (`CNN_POOL_OUT_WIDTH * `CNN_POOL_OUT_HEIGHT)
`define CNN_POOL_DEPTH        (`CNN_CONV_FILTERS * `CNN_POOL_PLANE_SIZE)
`define CNN_FC_INPUTS         `CNN_POOL_DEPTH
`define CNN_NUM_CLASSES        3
`define CNN_FC_W_DEPTH        (`CNN_NUM_CLASSES * `CNN_FC_INPUTS)
`define CNN_FC_B_DEPTH        `CNN_NUM_CLASSES

`define CNN_PIXEL_WIDTH        8
`define CNN_WEIGHT_WIDTH       8
`define CNN_BIAS_WIDTH        32
`define CNN_CONV_ACC_WIDTH    24
`define CNN_ACT_WIDTH          8
`define CNN_ACT_MAX          127
`define CNN_LOGIT_WIDTH       32
`define CNN_CLASS_WIDTH        2
`define CNN_CYCLE_WIDTH       20
// Decisions D19/D20: 20-bit count, at most 120000 clocks per real inference.
`define CNN_TARGET_CYCLES  120000

// Explicit address widths keep the header compatible with Verilog-2001.
// Recalculate these widths if the architecture or number of images changes.
`define CNN_IMAGE_ADDR_WIDTH  15
`define CNN_IMAGE_OFFSET_WIDTH 11
`define CNN_FMAP_ADDR_WIDTH   13
`define CNN_POOL_ADDR_WIDTH    11
`define CNN_CONV_W_ADDR_WIDTH  6
`define CNN_CONV_B_ADDR_WIDTH  2
`define CNN_FC_W_ADDR_WIDTH   13
`define CNN_FC_B_ADDR_WIDTH    2

`define CNN_CLASS_LEFT        2'd0
`define CNN_CLASS_STRAIGHT    2'd1
`define CNN_CLASS_RIGHT       2'd2

// Build-time configuration generated from mem/quant_params.txt.
// No reference/training values are silently substituted when absent.
`ifdef CNN_USE_QUANT_CONFIG
`include "cnn_quant_params.vh"
`endif
`endif
