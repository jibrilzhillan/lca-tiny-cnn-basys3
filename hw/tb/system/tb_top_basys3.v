// tb_top_basys3.v
// Full board-level simulation.
//
// Power-on state, all 16 images with bouncy presses, latency view, press during BUSY,
// switch moved during a run, reset during a run.
//   USE_STUB = 1: runs on cnn_core_stub, expected values follow the stub
//   USE_STUB = 0: runs on cnn_core, expected values come from expected_class.mem and test_labels.mem

`timescale 1ns / 1ps

module tb_top_basys3;

    localparam USE_STUB = 1;
    localparam STUB_CYCLES = 20'd106042;
    localparam TIMEOUT = 150000;      // cycles, more than one run

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg  [15:0] sw = 16'h0000;
    reg         btnC = 1'b0;
    reg         btnU = 1'b0;
    wire [15:0] led;
    wire [6:0]  seg;
    wire        dp;
    wire [3:0]  an;

    top_basys3 #(.SIM(1), .USE_STUB(USE_STUB)) dut (
        .clk(clk), .sw(sw), .btnC(btnC), .btnU(btnU),
        .led(led), .seg(seg), .dp(dp), .an(an)
    );

    // Expected patterns, active low, g f e d c b a
    localparam [6:0] L = 7'b1000111, F = 7'b0001110, S = 7'b0010010, T = 7'b0000111,
                     R = 7'b0101111, DASH = 7'b0111111, BLANK = 7'b1111111;

    function [6:0] hex7(input [3:0] h);
        case (h)
            4'h0: hex7 = 7'b1000000;  4'h1: hex7 = 7'b1111001;
            4'h2: hex7 = 7'b0100100;  4'h3: hex7 = 7'b0110000;
            4'h4: hex7 = 7'b0011001;  4'h5: hex7 = 7'b0010010;
            4'h6: hex7 = 7'b0000010;  4'h7: hex7 = 7'b1111000;
            4'h8: hex7 = 7'b0000000;  4'h9: hex7 = 7'b0010000;
            4'hA: hex7 = 7'b0001000;  4'hB: hex7 = 7'b0000011;
            4'hC: hex7 = 7'b1000110;  4'hD: hex7 = 7'b0100001;
            4'hE: hex7 = 7'b0000110;  4'hF: hex7 = 7'b0001110;
        endcase
    endfunction

    // LED groups
    localparam [15:0] BAR_L = 16'b1110_0000_0000_0000, BAR_S = 16'b0000_0001_1000_0000,
                      BAR_R = 16'b0000_0000_0000_0111, PASS = 16'h0800, FAIL = 16'h0400,
                      DONE = 16'h0010, BUSY = 16'h0008;

    reg [1:0] exp_class [0:15];
    reg [1:0] exp_label [0:15];

    integer errors = 0;
    integer checks = 0;
    integer runs = 0;                 // BUSY rising edges
    reg     busy_q = 1'b0;
    reg [19:0] latency;

    always @(posedge clk) begin
        busy_q <= led[3];
        if (led[3] === 1'b1 && busy_q === 1'b0) runs = runs + 1;
    end

    task check_led(input [31*8-1:0] what, input [15:0] exp);
        begin
            checks = checks + 1;
            if (led !== exp) begin
                errors = errors + 1;
                if (errors <= 10) $display("MISMATCH %0s: led expected %h actual %h", what, exp, led);
            end else begin
                $display("check %0s: led %h OK", what, led);
            end
        end
    endtask

    task check_int(input [31*8-1:0] what, input integer exp, input integer actual);
        begin
            checks = checks + 1;
            if (exp !== actual) begin
                errors = errors + 1;
                if (errors <= 10) $display("MISMATCH %0s: expected %0d actual %0d", what, exp, actual);
            end else begin
                $display("check %0s: %0d OK", what, actual);
            end
        end
    endtask

    // Reads all four digits off the scanned pins and compares them
    task check_digits(input [31*8-1:0] what, input [6:0] e3, input [6:0] e2,
                      input [6:0] e1, input [6:0] e0);
        reg [6:0] d [0:3];
        reg [3:0] seen;
        integer   n;
        begin
            seen = 4'b0000;
            for (n = 0; n < 40 && seen != 4'b1111; n = n + 1) begin
                @(negedge clk);
                case (an)
                    4'b1110: begin d[0] = seg; seen[0] = 1'b1; end
                    4'b1101: begin d[1] = seg; seen[1] = 1'b1; end
                    4'b1011: begin d[2] = seg; seen[2] = 1'b1; end
                    4'b0111: begin d[3] = seg; seen[3] = 1'b1; end
                    default: ;
                endcase
            end
            checks = checks + 1;
            if (seen != 4'b1111 || d[3] !== e3 || d[2] !== e2 || d[1] !== e1 || d[0] !== e0 || dp !== 1'b1) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("MISMATCH %0s: digits expected %b %b %b %b actual %b %b %b %b",
                             what, e3, e2, e1, e0, d[3], d[2], d[1], d[0]);
            end else begin
                $display("check %0s: digits OK", what);
            end
        end
    endtask

    task settle;
        repeat (10) @(negedge clk);
    endtask

    // Press with contact bounce at both ends, shorter than the debounce time
    task press;
        integer b;
        begin
            for (b = 0; b < 6; b = b + 1) begin
                btnC = ~btnC;
                repeat (3) @(negedge clk);
            end
            btnC = 1'b1;
            repeat (40) @(negedge clk);
            for (b = 0; b < 6; b = b + 1) begin
                btnC = ~btnC;
                repeat (3) @(negedge clk);
            end
            btnC = 1'b0;
            repeat (40) @(negedge clk);
        end
    endtask

    task wait_idle;
        integer n;
        begin
            n = 0;
            while (led[3] !== 1'b0 && n < TIMEOUT) begin
                @(negedge clk);
                n = n + 1;
            end
            if (n == TIMEOUT) begin
                errors = errors + 1;
                $display("MISMATCH wait_idle: BUSY did not fall within %0d cycles", TIMEOUT);
            end
            settle;
        end
    endtask

    function [15:0] result_led(input [1:0] c, input [1:0] lbl);
        begin
            result_led = DONE;
            case (c)
                2'd0:    result_led = result_led | BAR_L;
                2'd1:    result_led = result_led | BAR_S;
                default: result_led = result_led | BAR_R;
            endcase
            result_led = result_led | ((c == lbl) ? PASS : FAIL);
        end
    endfunction

    function [6:0] char1(input [1:0] c);
        char1 = (c == 2'd0) ? L : (c == 2'd1) ? S : R;
    endfunction

    function [6:0] char0(input [1:0] c);
        char0 = (c == 2'd0) ? F : T;
    endfunction

    integer i, runs_before;

    initial begin
        if (USE_STUB) begin
            for (i = 0; i < 16; i = i + 1) begin
                exp_class[i] = i % 3;
                exp_label[i] = (i == 15) ? 2'd1 : i % 3;
            end
        end else begin
            $readmemh("expected_class.mem", exp_class);
            $readmemh("test_labels.mem", exp_label);
        end

        // Power-on: no button touched
        repeat (40) @(negedge clk);
        check_led("power-on leds", 16'h0000);
        check_digits("power-on display", hex7(4'd0), BLANK, DASH, DASH);
        check_int("runs after power-on", 0, runs);

        // All 16 images
        for (i = 0; i < 16; i = i + 1) begin
            // Drive the complete switch word. XSim 2019.2 corrupts this
            // loop's variable part-select stimulus (observed sw=0x3210).
            // During this loop all upper switches are intentionally zero.
            sw = i;
            settle;
            check_digits("image on digit 3", hex7(i[3:0]), BLANK,
                         (i == 0) ? DASH : char1(exp_class[i-1]),
                         (i == 0) ? DASH : char0(exp_class[i-1]));
            runs_before = runs;
            press;
            check_int("BUSY during run", 1, led[3]);
            wait_idle;
            check_int("one run per press", runs_before + 1, runs);
            check_led("result leds", result_led(exp_class[i], exp_label[i]));
            check_digits("result display", hex7(i[3:0]), BLANK, char1(exp_class[i]), char0(exp_class[i]));
        end

        // Latency view: the LEDs stay, the digits show the count
        sw[14] = 1'b1;
        settle;
        latency = dut.u_disp.cycle_count;
        if (USE_STUB) check_int("cycle_count", STUB_CYCLES, latency);
        check_digits("latency display", hex7(latency[15:12]), hex7(latency[11:8]),
                     hex7(latency[7:4]), hex7(latency[3:0]));
        sw[13]=1; settle;
        check_digits("latency high page",hex7(0),hex7(0),hex7(0),hex7(latency[19:16]));
        sw[13]=0; settle;
        check_led("leds in latency view", result_led(exp_class[15], exp_label[15]));
        sw[14] = 1'b0;

        // A second press during BUSY is ignored and the latency doesn't change
        sw[3:0] = 4'd1;
        settle;
        runs_before = runs;
        press;
        press;
        wait_idle;
        check_int("press during BUSY ignored", runs_before + 1, runs);
        check_led("after press during BUSY", result_led(exp_class[1], exp_label[1]));
        check_int("latency same after press", latency, dut.u_disp.cycle_count);

        // Switch moved during a run: the result still belongs to the image that ran
        sw[3:0] = 4'd3;
        settle;
        press;
        sw[3:0] = 4'd15;
        wait_idle;
        check_led("switch moved during run", result_led(exp_class[3], exp_label[3]));
        check_digits("digit 3 follows the switch", hex7(4'd15), BLANK, char1(exp_class[3]), char0(exp_class[3]));

        // Reset during a run clears everything; the next run is correct
        sw[3:0] = 4'd2;
        settle;
        press;
        check_int("BUSY before reset", 1, led[3]);
        btnU = 1'b1;
        repeat (40) @(negedge clk);
        check_led("reset held", 16'h0000);
        check_int("anodes off during reset", 15, an);
        btnU = 1'b0;
        repeat (40) @(negedge clk);
        check_led("after reset", 16'h0000);
        check_digits("display after reset", hex7(4'd2), BLANK, DASH, DASH);
        press;
        wait_idle;
        check_led("run after reset", result_led(exp_class[2], exp_label[2]));

        $display("%0d checks, %0d errors, %0d runs", checks, errors, runs);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule
