// tb_utils.vh
// Shared self-checking tasks, limited mismatch reporting and PASS/FAIL.

// Include inside each testbench module, after declaring integer errors.
// Intentionally no include guard: each module needs its own task scope.
reg test_finished;
initial test_finished = 1'b0;

task check;
    input condition;
    input [8*100-1:0] message;
    begin
        if (condition !== 1'b1) begin
            if (errors < 10)
                $display("ERROR time=%0t expected=1 actual=%b: %0s", $time, condition, message);
            errors = errors + 1;
        end
    end
endtask

task compare_word;
    input [31:0] actual;
    input [31:0] expected;
    input integer index;
    input [8*40-1:0] label;
    begin
        if (actual !== expected) begin
            if (errors < 10)
                $display("ERROR %0s index=%0d expected=%h actual=%h", label, index, expected, actual);
            errors = errors + 1;
        end
    end
endtask

task report_test;
    begin
        test_finished = 1'b1;
        if (errors == 0) $display("TEST PASSED");
        else $display("TEST FAILED: %0d errors", errors);
    end
endtask
