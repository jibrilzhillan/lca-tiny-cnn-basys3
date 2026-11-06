# create_project.tcl
# Recreates the Vivado project in hw/vivado/build/ from the sources in git.
#
# Batch:  vivado -mode batch -source hw/vivado/create_project.tcl [-tclargs <top> [<generic>]]
# GUI:    Tcl Console -> source hw/vivado/create_project.tcl
# <top> defaults to top_basys3 (the real design). Use bringup_top for the H0 board test.
# <generic> is optional: top_basys3 USE_STUB=1 builds the board side without the CNN.

set top top_basys3
set generic ""
if {[info exists argv] && [llength $argv] > 0} {
    set top [lindex $argv 0]
}
if {[info exists argv] && [llength $argv] > 1} {
    set generic [join [lrange $argv 1 end] =]  ;# vivado.bat splits USE_STUB=1 at the = sign
}

# Repo root = two folders up from this script, so it works from any directory
set root  [file normalize [file join [file dirname [info script]] .. ..]]
set build [file join $root hw vivado build]

set quant_include ""
set needs_quant [expr {$top eq "cnn_core" || ($top eq "top_basys3" && ![regexp {USE_STUB=1} $generic])}]
if {$needs_quant} {
    foreach name {test_images.mem test_labels.mem conv_weight.mem conv_bias.mem fc_weight.mem fc_bias.mem} {
        if {![file exists [file join $root mem $name]]} {
            error "Missing model memory: mem/$name. Add the model export; use USE_STUB=1 for board-only work."
        }
    }
    set quant_file [file join $root mem quant_params.txt]
    if {![file exists $quant_file]} {error "Missing model export: $quant_file. Use bringup_top or USE_STUB=1 for board-only work."}
    set python python
    if {[info exists ::env(CNN_PYTHON)]} {set python $::env(CNN_PYTHON)}
    set quant_include [file join $build quant]
    puts [exec $python -E -B [file join $root hw tools prepare_quant_params.py] --input $quant_file --output [file join $quant_include cnn_quant_params.vh] 2>@1]
}

create_project lca_tiny_cnn $build -part xc7a35tcpg236-1 -force
set_property target_language Verilog [current_project]

# Design sources: the whole rtl/ tree (add_files on a folder is recursive)
add_files [list [file join $root hw rtl]]
set_property include_dirs [list [file join $root hw rtl include]] [get_filesets sources_1]

# .mem files: added once here, so $readmemh only needs the bare file name
set mems [glob -nocomplain [file join $root mem *.mem]]
if {[llength $mems] > 0} {
    add_files $mems
}

# Testbenches
add_files -fileset sim_1 [list [file join $root hw tb]]
set_property include_dirs [list [file join $root hw rtl include] [file join $root hw tb common]] [get_filesets sim_1]

# Constraints: only basys3.xdc (Basys-3-Master.xdc in the same folder is a reference copy)
add_files -fileset constrs_1 [list [file join $root hw constr basys3.xdc]]

if {$quant_include ne ""} {
    foreach fileset {sources_1 sim_1} {
        set_property include_dirs [concat [get_property include_dirs [get_filesets $fileset]] [list $quant_include]] [get_filesets $fileset]
        set_property verilog_define {CNN_USE_QUANT_CONFIG} [get_filesets $fileset]
    }
}

set_property top $top [get_filesets sources_1]
if {$generic ne ""} {
    set_property generic $generic [get_filesets sources_1]
}
update_compile_order -fileset sources_1

puts "Project created: [file join $build lca_tiny_cnn.xpr] (top = $top $generic)"
