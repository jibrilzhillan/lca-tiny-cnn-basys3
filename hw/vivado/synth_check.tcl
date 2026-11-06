# synth_check.tcl
# Quick synthesis of one module to catch code that won't synthesize. No project, no implementation.
# Prints the LUT/FF/DSP/BRAM/latch counts; reports go to hw/vivado/build/reports/.
#
# Batch:  vivado -mode batch -nojournal -nolog -notrace -source hw/vivado/synth_check.tcl -tclargs <module> [<generic>]
#         e.g. -tclargs cnn_core
#              -tclargs top_basys3 USE_STUB=1
# top_basys3 gets the XDC. Any other module runs out of context (ports are not pins).

set module [lindex $argv 0]
set generic [join [lrange $argv 1 end] =]  ;# vivado.bat splits USE_STUB=1 at the = sign

set root    [file normalize [file join [file dirname [info script]] .. ..]]
set rtl     [file join $root hw rtl]
set reports [file join $root hw vivado build reports]
file mkdir $reports

set part xc7a35tcpg236-1
create_project -in_memory -part $part

foreach dir {lib cnn cnn/conv cnn/classifier board} {
    foreach f [glob -nocomplain -directory [file join $rtl $dir] *.v] { read_verilog $f }
}
set mems [glob -nocomplain [file join $root mem *.mem]]
if {[llength $mems] > 0} { read_mem $mems }

set args [list -top $module -part $part -include_dirs [file join $rtl include]]
if {$generic ne ""} { lappend args -generic $generic }
if {$module eq "top_basys3"} {
    read_xdc [file join $root hw constr basys3.xdc]
} else {
    lappend args -mode out_of_context
}

synth_design {*}$args

report_utilization -file [file join $reports ${module}_synth_utilization.txt]
report_methodology -file [file join $reports ${module}_synth_methodology.txt]
if {$module eq "top_basys3"} {
    report_timing_summary -file [file join $reports ${module}_synth_timing.txt]
}

puts ""
puts "$module $generic:"
foreach {name ref} {LUT LUT* FF FD* DSP DSP48E1 BRAM36 RAMB36E1 BRAM18 RAMB18E1 LATCH LD*} {
    puts [format "  %-7s %d" $name [llength [get_cells -hierarchical -filter "REF_NAME =~ $ref"]]]
}
puts "  Reports: $reports"
