# run_tests.tcl
# Isolated self-checking unit, synthetic integration and board-stub tests.
# Usage: vivado -mode batch -source hw/vivado/run_tests.tcl
# Optional -tclargs: <all|core|classifier|board|quant|production|name-filter> <build-dir> <python3> [<mem-dir>]
# Real CNN tests use explicit exports; missing sources/data are reported BLOCKED.

proc capture_tool {command logfile} {
    set code [catch {exec {*}$command >$logfile 2>@1} message]
    set f [open $logfile r]; set output [read $f]; close $f
    if {$code} {return -code error "$message\n$output"}
    return $output
}

proc run_team_tests {root arguments} {
    set filter all
    if {[llength $arguments]>0} {set filter [lindex $arguments 0]}
    set work [file join $root hw vivado build tests [clock milliseconds]]
    if {[llength $arguments]>1} {set work [file normalize [lindex $arguments 1]]}
    set python python
    if {[llength $arguments]>2} {set python [lindex $arguments 2]}
    set memdir [file join $root mem]
    if {[llength $arguments]>3} {set memdir [file normalize [lindex $arguments 3]]}
    file mkdir $work
    set hw [file join $root hw]
    set ext [expr {$::tcl_platform(platform) eq "windows" ? ".bat" : ""}]
    set bin [file join $::env(XILINX_VIVADO) bin]
    set xvlog [file join $bin xvlog$ext]
    set xelab [file join $bin xelab$ext]
    set xsim [file join $bin xsim$ext]
    # name, group, tb, source set, fixture family, optional define
    set core {rtl/lib/rom.v rtl/lib/ram.v rtl/cnn/cnn_ctrl.v rtl/cnn/cnn_core.v}
    set classifier {rtl/cnn/classifier/maxpool_engine.v rtl/cnn/classifier/fc_engine.v rtl/cnn/classifier/argmax3.v}
    set mocks {tb/common/mocks/conv_engine.v tb/common/mocks/maxpool_engine.v tb/common/mocks/fc_engine.v tb/common/mocks/argmax3.v}
    set conv {rtl/cnn/conv/mac.v rtl/cnn/conv/relu_requant.v rtl/cnn/conv/address_generator.v rtl/cnn/conv/conv_engine.v}
    set tests {
        {U1_mac production tb/conv/tb_mac.v {rtl/cnn/conv/mac.v} {} {}}
        {U2_relu_requant production tb/conv/tb_relu_requant.v {rtl/cnn/conv/relu_requant.v} scales CNN_USE_QUANT_CONFIG}
        {U3_I1_conv production tb/conv/tb_conv_engine.v {rtl/lib/rom.v rtl/lib/ram.v rtl/cnn/conv/mac.v rtl/cnn/conv/relu_requant.v rtl/cnn/conv/address_generator.v rtl/cnn/conv/conv_engine.v} production CNN_USE_QUANT_CONFIG}
        {tb_rom core tb/lib/tb_rom.v {rtl/lib/rom.v} core {}}
        {tb_ram core tb/lib/tb_ram.v {rtl/lib/ram.v} core {}}
        {U7_cnn_ctrl core tb/cnn/tb_cnn_ctrl.v {rtl/cnn/cnn_ctrl.v} {} {}}
        {U4_maxpool_engine classifier tb/classifier/tb_maxpool_engine.v {rtl/lib/ram.v rtl/cnn/classifier/maxpool_engine.v} classifier {}}
        {U5_fc_engine classifier tb/classifier/tb_fc_engine.v {rtl/lib/rom.v rtl/lib/ram.v rtl/cnn/classifier/fc_engine.v} classifier {}}
        {U6_argmax3 classifier tb/classifier/tb_argmax3.v {rtl/cnn/classifier/argmax3.v} {} {}}
        {U8_btn_debounce board tb/lib/tb_btn_debounce.v {rtl/lib/btn_debounce.v} {} {}}
        {U9_seg7_mux board tb/board/tb_seg7_mux.v {rtl/board/seg7_mux.v rtl/board/hex_to_7seg.v} {} {}}
        {result_display board tb/board/tb_result_display.v {rtl/board/result_display.v rtl/board/hex_to_7seg.v} {} {}}
        {top_basys3 board tb/system/tb_top_basys3.v {rtl/board/top_basys3.v rtl/board/cnn_core_stub.v rtl/lib/btn_debounce.v rtl/board/result_display.v rtl/board/hex_to_7seg.v rtl/board/seg7_mux.v} {} {}}
        {quant_config quant tb/cnn/tb_quant_config.v {} quant CNN_USE_QUANT_CONFIG}
    }
    lappend tests [list conv_directed production tb/conv/tb_conv_engine_directed.v [concat {rtl/lib/rom.v} $conv] production CNN_USE_QUANT_CONFIG]
    lappend tests [list wiring_core core tb/system/tb_cnn_core_wiring.v [concat $core $mocks] core CNN_CORE_WIRING_TEST]
    lappend tests [list classifier_core classifier tb/system/tb_classifier_core.v [concat $core $classifier {tb/common/mocks/conv_engine.v}] classifier CNN_CORE_WIRING_TEST]
    lappend tests [list I2_conv_pool production tb/system/tb_conv_pool.v [concat $core $classifier $conv] production CNN_USE_QUANT_CONFIG]
    lappend tests [list I3_I4_I5_cnn_core production tb/system/tb_cnn_core.v [concat $core $classifier $conv] production CNN_USE_QUANT_CONFIG]
    lappend tests [list top_basys3_real production tb/system/tb_top_basys3_real.v [concat $core $classifier $conv {rtl/board/top_basys3.v rtl/lib/btn_debounce.v rtl/board/result_display.v rtl/board/hex_to_7seg.v rtl/board/seg7_mux.v}] production CNN_USE_QUANT_CONFIG]
    set results {}; set count 0; set fail 0; set blocked 0
    set exact_filter 0
    foreach candidate $tests {if {[lindex $candidate 0] eq $filter} {set exact_filter 1}}
    set prepared [dict create]
    set ::env(CNN_TEST_TMPDIR) [file join $work python-temp]
    file mkdir $::env(CNN_TEST_TMPDIR)
    foreach test $tests {
        lassign $test name group tb rtl family define
        if {$exact_filter} {
            if {$name ne $filter} {continue}
        } elseif {$filter ne "all" && $filter ne $group && [string first $filter $name]<0} {continue}
        incr count
        set dir [file join $work $name]
        file mkdir $dir
        set log [file join $dir run.log]
        set status PASS; set detail ""; set out ""
        set start [clock milliseconds]
        set sources {}
        foreach relative [concat $rtl [list $tb]] {lappend sources [file join $hw $relative]}
        # Placeholder or missing files are not passing tests.
        foreach source $sources {
            if {![file exists $source]} {set status BLOCKED; set detail "missing source: [file tail $source]"; break}
            set f [open $source r]; set content [read $f]; close $f
            if {![regexp -line {^\s*module\s+} $content]} {set status BLOCKED; set detail "placeholder: [file tail $source]"; break}
        }
        if {$status eq "PASS" && $family in {production scales}} {
            set required {quant_params.txt}
            if {$family eq "production"} {lappend required test_images.mem conv_weight.mem conv_bias.mem fc_weight.mem fc_bias.mem golden/conv_all.mem golden/pool_all.mem golden/logits_all.mem golden/expected_class.mem test_labels.mem}
            foreach relative $required {
                if {![file exists [file join $memdir $relative]]} {set status BLOCKED; set detail "missing model export: $relative"; break}
            }
        }
        if {$status eq "PASS"} {
            set old [pwd]
            if {[catch {
                set incs [list -i [file join $hw rtl include] -i [file join $hw tb common]]
                if {$family in {core classifier}} {
                    set vectors [file join $work vectors_$family]
                    if {![dict exists $prepared $family]} {
                        set script [expr {$family eq "core" ? "system/generate_core_fixtures.py" : "classifier/generate_classifier_fixtures.py"}]
                        append out [exec $python -E -B [file join $hw tb $script] --output-dir $vectors 2>@1] "\n"
                        dict set prepared $family 1
                    }
                    foreach memory [glob [file join $vectors *.mem]] {file copy -force $memory $dir}
                }
                if {$family eq "quant"} {
                    append out [exec $python -E -B [file join $hw tb common test_quant_params.py] 2>@1] "\n"
                    set q [file join $dir quant_fixture.txt]
                    set f [open $q w]; puts $f "# Synthetic parser test only\nFw1=7\nFa=6\nFw2=8\nS1=9"; close $f
                    append out [exec $python -E -B [file join $hw tools prepare_quant_params.py] --input $q --output [file join $dir cnn_quant_params.vh] 2>@1] "\n"
                    lappend incs -i $dir
                }
                if {$family in {production scales}} {
                    if {$family eq "production"} {
                        if {![dict exists $prepared export]} {
                            append out [exec $python -E -B [file join $hw tools verify_export.py] --mem-dir $memdir --addresses [file join $work conv_read_addresses.mem] 2>@1] "\n"
                            dict set prepared export 1
                        }
                        foreach memory [concat [glob [file join $memdir *.mem]] [glob [file join $memdir golden *.mem]]] {file copy -force $memory $dir}
                        file copy -force [file join $work conv_read_addresses.mem] $dir
                    }
                    append out [exec $python -E -B [file join $hw tools prepare_quant_params.py] --input [file join $memdir quant_params.txt] --output [file join $dir cnn_quant_params.vh] 2>@1] "\n"
                    lappend incs -i $dir
                }
                set defs {}
                if {$define ne ""} {set defs [list -d $define]}
                cd $dir
                set watchdog [file join $dir regression_timeout.v]
                set wf [open $watchdog w]
                puts $wf {`timescale 1ns/1ps}
                puts $wf {module regression_timeout; initial begin #100000000; $display("TEST FAILED: regression watchdog"); $finish; end endmodule}
                close $wf
                lappend sources $watchdog
                append out [capture_tool [list $xvlog -nolog {*}$incs {*}$defs {*}$sources] [file join $dir compile.log]] "\n"
                set top [file rootname [file tail $tb]]
                set snapshot snap_$name
                append out [capture_tool [list $xelab -nolog -debug typical -s $snapshot $top regression_timeout] [file join $dir elaborate.log]] "\n"
                set f [open run_sim.tcl w]; puts $f "run 100 ms\nquit"; close $f
                set simulation [capture_tool [list $xsim -nolog $snapshot -onfinish quit -onerror quit -R] [file join $dir simulate.log]]
                append out $simulation "\n"
                if {[regexp -line {^TEST FAILED} $simulation] || ![regexp -line {^TEST PASSED\s*$} $simulation] || ![regexp {\$finish called} $simulation]} {
                    error "missing clean TEST PASSED and completion; inspect run.log"
                }
            } message]} {set status FAIL; set detail $message; append out "\nFAIL: $message\n"}
            cd $old
        }
        if {$status eq "FAIL"} {incr fail}
        if {$status eq "BLOCKED"} {incr blocked; append out "BLOCKED: $detail\n"}
        set f [open $log w]; puts $f $out; close $f
        lappend results [list $name $status [format %.1f [expr {([clock milliseconds]-$start)/1000.0}]] $detail]
        puts "$status $name"
    }
    if {$count==0} {error "No tests match filter '$filter'"}
    set f [open [file join $work results.txt] w]
    foreach result $results {lassign $result name status seconds detail; puts $f "$status $name ($seconds s) $detail"}
    puts $f "MODEL DIRECTORY: $memdir"
    puts $f "SCOPE: production tests use the real conv and classifier engines with the selected export. Mock/stub tests remain separate."
    if {[file exists [file join $memdir SOURCE_PROVENANCE.txt]]} {
        set provenance [open [file join $memdir SOURCE_PROVENANCE.txt] r]
        puts $f [read $provenance]; close $provenance
    }
    close $f
    puts "RESULT: $count tests, $fail failures, $blocked blocked. Logs: $work"
    if {$fail>0 || $blocked>0} {return -code error "Regression incomplete: $fail failed, $blocked blocked"}
}
set root [file normalize [file join [file dirname [info script]] .. ..]]
if {[catch {run_team_tests $root $argv} message]} {puts stderr $message; exit 1}
exit 0
