# program_board.tcl
# Programs the Basys3 over USB (JTAG) with the bitstream from build_bitstream.tcl.
# Board: JP1 jumper on JTAG, USB cable in, power switch on.
#
# Batch:  vivado -mode batch -source hw/vivado/program_board.tcl

set root  [file normalize [file join [file dirname [info script]] .. ..]]
set build [file join $root hw vivado build]

open_project [file join $build lca_tiny_cnn.xpr]
set top [get_property top [get_filesets sources_1]]
set bit [file join [get_property DIRECTORY [get_runs impl_1]] ${top}.bit]
if {![file exists $bit]} {
    error "No bitstream at $bit, run build_bitstream.tcl first"
}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a35t_0] 0]
if {$dev eq ""} {
    error "No xc7a35t found on the cable. Is the board powered on?"
}
set dev_name [get_property NAME $dev]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
close_hw_manager

puts "Programmed $dev_name with $bit"
