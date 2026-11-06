# build_bitstream.tcl
# Synthesis -> implementation -> bitstream for the project made by create_project.tcl.
# Writes timing and utilization reports to hw/vivado/build/reports/ and archives
# them, with build_info.txt, in report/builds/Bnn_<commit>/.
#
# Batch:  vivado -mode batch -source hw/vivado/build_bitstream.tcl

set root    [file normalize [file join [file dirname [info script]] .. ..]]
set build   [file join $root hw vivado build]
set reports [file join $build reports]
file mkdir $reports

open_project [file join $build lca_tiny_cnn.xpr]
set top [get_property top [get_filesets sources_1]]
puts "Building top: $top [get_property generic [get_filesets sources_1]]"

# The real core needs the quant config that create_project.tcl adds only when it is
# run with that top. Without it conv_engine synthesizes with S1 = -1: the bitstream
# builds without error but the conv outputs are zero (the board shows rt for nearly
# every image). This happens when the top is switched in the GUI instead.
set real_core [expr {$top eq "cnn_core" || ($top eq "top_basys3" && ![regexp {USE_STUB=1} [get_property generic [get_filesets sources_1]]])}]
if {$real_core && [lsearch [get_property verilog_define [get_filesets sources_1]] CNN_USE_QUANT_CONFIG] < 0} {
    error "Top $top needs the quant config from mem/quant_params.txt, which this project doesn't have.\
           Rerun create_project.tcl (default top_basys3) instead of changing the top in the GUI."
}

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis failed, see [get_property DIRECTORY [get_runs synth_1]]/runme.log"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation failed, see [get_property DIRECTORY [get_runs impl_1]]/runme.log"
}

open_run impl_1
report_utilization    -file [file join $reports ${top}_utilization.txt]
report_timing_summary -file [file join $reports ${top}_timing.txt]

set bit [file join [get_property DIRECTORY [get_runs impl_1]] ${top}.bit]
set wns [get_property STATS.WNS [get_runs impl_1]]
set tns [get_property STATS.TNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]

# Archive this build in report/builds/Bnn_<commit>/ (tracked in git), so each row of
# report/implementation_log.md points at one commit and its reports. Build numbers
# count up from the highest existing Bnn. A tree with uncommitted hw/ or mem/ changes
# gets a _dirty suffix: commit first if the build has to be reproducible.
set archive_root [file join $root report builds]
file mkdir $archive_root
set n 0
foreach d [glob -nocomplain -types d -directory $archive_root B*] {
    if {[regexp {^B([0-9]+)_} [file tail $d] -> k]} {
        scan $k %d k
        if {$k > $n} {set n $k}
    }
}
set build_id [format B%02d [expr {$n + 1}]]

set commit unknown
set branch unknown
set dirty  unknown
catch {set commit [exec git -C $root rev-parse --short HEAD]}
catch {set branch [exec git -C $root rev-parse --abbrev-ref HEAD]}
catch {set dirty [expr {[exec git -C $root status --porcelain -- hw mem] eq "" ? "no" : "yes"}]}

set archive [file join $archive_root ${build_id}_${commit}[expr {$dirty eq "yes" ? "_dirty" : ""}]]
file mkdir $archive
file copy -force [file join $reports ${top}_utilization.txt] [file join $archive utilization.txt]
file copy -force [file join $reports ${top}_timing.txt]      [file join $archive timing.txt]
report_utilization -hierarchical       -file [file join $archive utilization_hier.txt]
report_timing -max_paths 10 -sort_by slack -file [file join $archive critical_paths.txt]
report_drc                             -file [file join $archive drc.txt]

# Synthesis warnings for check S1 (the runme.log is overwritten by the next build)
set out [open [file join $archive synth_warnings.txt] w]
set fh  [open [file join [get_property DIRECTORY [get_runs synth_1]] runme.log] r]
while {[gets $fh line] >= 0} {
    if {[regexp {^(CRITICAL WARNING|WARNING|ERROR)} $line]} {puts $out $line}
}
close $fh
close $out

# First "| <name> | <used> |" row of the utilization report
proc util_used {text name} {
    set re [format {\|\s*%s\*?\s*\|\s*([0-9.]+)} $name]
    if {[regexp $re $text -> v]} {return $v}
    return ?
}
set fh [open [file join $reports ${top}_utilization.txt] r]
set util [read $fh]
close $fh
set lut  [util_used $util {Slice LUTs}]
set ff   [util_used $util {Slice Registers}]
set bram [util_used $util {Block RAM Tile}]
set dsp  [util_used $util DSPs]

set fh [open [file join $archive build_info.txt] w]
puts $fh "build    $build_id"
puts $fh "date     [clock format [clock seconds] -format {%Y-%m-%d %H:%M}]"
puts $fh "commit   $commit ($branch)"
puts $fh "dirty    $dirty (uncommitted changes under hw/ or mem/)"
puts $fh "vivado   [version -short]"
puts $fh "top      $top"
puts $fh "generic  [get_property generic [get_filesets sources_1]]"
puts $fh "WNS      $wns ns"
puts $fh "TNS      $tns ns"
puts $fh "WHS      $whs ns"
puts $fh "LUT      $lut"
puts $fh "FF       $ff"
puts $fh "BRAM     $bram tiles"
puts $fh "DSP      $dsp"
close $fh

puts "Bitstream: $bit"
puts "Worst negative slack: $wns ns (must be >= 0)"
puts "Reports:   $reports"
puts "Archived:  $archive"
puts "Row for report/implementation_log.md (fill in the change and board columns):"
puts "| $build_id | $commit | <change> | $wns | $tns | $lut | $ff | $bram | $dsp | not tested |"
