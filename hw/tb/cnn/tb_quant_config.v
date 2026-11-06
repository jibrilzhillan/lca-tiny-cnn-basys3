// tb_quant_config.v
// Verify build-generated scales reach RTL; fixture values are not the trained model's.
`ifdef CNN_USE_QUANT_CONFIG
`timescale 1ns/1ps
`include "cnn_params.vh"
module tb_quant_config;
    integer errors=0;
    `include "tb_utils.vh"
    initial begin
        check(`CNN_FW1==7 && `CNN_FA==6 && `CNN_FW2==8,"export scale import mismatch");
        check(`CNN_S1==9 && `CNN_REQUANT_SHIFT==9,"requant shift mismatch");
        check(`CNN_CONV_BIAS_FRAC==15 && `CNN_LOGIT_FRAC==14,"derived scale mismatch");
        check(`CNN_CYCLE_WIDTH==20 && `CNN_TARGET_CYCLES==120000,"D19/D20 mismatch");
        report_test; $finish;
    end
endmodule
`endif
