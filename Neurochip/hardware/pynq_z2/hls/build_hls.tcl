set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set build_dir [file normalize [file join $root_dir build hls]]
set ip_out_dir [file normalize [file join $root_dir build ip]]
set project_name snn_overlay_hls
set solution_name solution1
set export_zip_path [file normalize [file join $build_dir export.zip]]

file mkdir $build_dir
file mkdir $ip_out_dir

cd $build_dir
open_project -reset $project_name
set_top snn_overlay_engine
add_files $script_dir/snn_overlay_engine.cpp
add_files $script_dir/snn_overlay_engine.hpp
add_files -tb $script_dir/snn_overlay_engine_tb.cpp
open_solution -reset $solution_name
set_part xc7z020clg400-1
create_clock -period 10 -name default

# Run the behavioural testbench before synthesis.  Overlay-v1 was synthesised
# and shipped without anything ever having executed the kernel.
csim_design

csynth_design
export_design -format ip_catalog \
    -vendor user.org \
    -library user \
    -ipname snn_overlay_engine \
    -version 2.0 \
    -output $export_zip_path

set packaged_ip_dir [file normalize [file join $build_dir $project_name $solution_name impl ip]]
if {![file exists $packaged_ip_dir]} {
    error "Expected packaged IP directory was not generated at $packaged_ip_dir"
}

file delete -force $ip_out_dir
file mkdir $ip_out_dir
foreach packaged_file [glob -nocomplain -directory $packaged_ip_dir *] {
    file copy -force $packaged_file $ip_out_dir
}
exit
