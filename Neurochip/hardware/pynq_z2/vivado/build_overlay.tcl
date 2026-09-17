set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set output_dir [file normalize [lindex $argv 0]]
if {$output_dir eq ""} {
    set output_dir [file normalize [file join $root_dir build out]]
}

set project_dir [file normalize [file join $root_dir build vivado]]
set ip_repo_dir [file normalize [file join $root_dir build ip]]
set manifest_path [file normalize [file join $root_dir overlay_manifest.json]]
set design_name snn_overlay_v2

file mkdir $project_dir
file mkdir $output_dir

create_project -force $design_name $project_dir -part xc7z020clg400-1
set_property ip_repo_paths $ip_repo_dir [current_project]
update_ip_catalog

set snn_engine_ip_defs [get_ipdefs -all "*:*:snn_overlay_engine:*"]
if {[llength $snn_engine_ip_defs] == 0} {
    error "No snn_overlay_engine IP definition was found under $ip_repo_dir. Run the HLS export first."
}
set snn_engine_vlnv [get_property VLNV [lindex $snn_engine_ip_defs 0]]

create_bd_design $design_name

create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_length_width {26} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
] [get_bd_cells axi_dma_0]

create_bd_cell -type ip -vlnv $snn_engine_vlnv snn_engine_0
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc_0
set_property -dict [list CONFIG.NUM_MI {2}] [get_bd_cells axi_smc_0]

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR"} [get_bd_cells processing_system7_0]

# HP0/HP1 carry the DMA stream in and out.  HP2 is new in v2: it carries the
# engine's own `m_axi gmem` master, which is how weights actually reach the
# fabric.  In v1 the weights were a raw BRAM port that nothing in this design
# was ever connected to, so every weight the engine read was zero.
set_property -dict [list \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP1 {1} \
    CONFIG.PCW_USE_S_AXI_HP2 {1} \
] [get_bd_cells processing_system7_0]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_dma_0/s_axi_lite_aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_smc_0/aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins snn_engine_0/ap_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/S_AXI_HP1_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/S_AXI_HP2_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_dma_0/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins axi_dma_0/axi_resetn]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins snn_engine_0/ap_rst_n]

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins snn_engine_0/in_stream]
connect_bd_intf_net [get_bd_intf_pins snn_engine_0/out_stream] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins axi_smc_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc_0/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_smc_0/M01_AXI] [get_bd_intf_pins snn_engine_0/s_axi_control]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list \
    Master "/axi_dma_0/M_AXI_MM2S" \
] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list \
    Master "/axi_dma_0/M_AXI_S2MM" \
] [get_bd_intf_pins processing_system7_0/S_AXI_HP1]

# The engine's weight/descriptor master.  Fail loudly rather than build a
# second bitstream that silently cannot read weights.
set gmem_pins [get_bd_intf_pins -quiet snn_engine_0/m_axi_gmem]
if {[llength $gmem_pins] == 0} {
    error "snn_engine_0 has no m_axi_gmem port. The HLS kernel must export its\
 weight master as `bundle=gmem` — without it the engine cannot read weights,\
 which is exactly the overlay-v1 defect this design exists to fix."
}
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list \
    Master "/snn_engine_0/m_axi_gmem" \
] [get_bd_intf_pins processing_system7_0/S_AXI_HP2]

assign_bd_address
save_bd_design

make_wrapper -files [get_files $project_dir/$design_name.srcs/sources_1/bd/$design_name/$design_name.bd] -top
add_files -norecurse $project_dir/$design_name.gen/sources_1/bd/$design_name/hdl/${design_name}_wrapper.v
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bit_path [file normalize [file join $project_dir $design_name.runs impl_1 ${design_name}_wrapper.bit]]
set hwh_path [file normalize [file join $project_dir $design_name.gen sources_1 bd $design_name hw_handoff $design_name.hwh]]

file copy -force $bit_path [file join $output_dir snn_overlay.bit]
file copy -force $hwh_path [file join $output_dir snn_overlay.hwh]
file copy -force $manifest_path [file join $output_dir overlay_manifest.json]

close_project
exit
