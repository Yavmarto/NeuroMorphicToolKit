from pathlib import Path


def _hardware_file(*parts: str) -> str:
    repo_root = Path(__file__).resolve().parents[2]
    return (repo_root / "hardware" / "pynq_z2" / Path(*parts)).read_text(encoding="utf-8")


def test_hls_build_script_opens_project_from_build_directory() -> None:
    build_hls_tcl = _hardware_file("hls", "build_hls.tcl")

    assert "set project_name snn_overlay_hls" in build_hls_tcl
    assert "set solution_name solution1" in build_hls_tcl
    assert "cd $build_dir" in build_hls_tcl
    assert "open_project -reset $project_name" in build_hls_tcl
    assert "open_solution -reset $solution_name" in build_hls_tcl
    assert "-vendor user.org" in build_hls_tcl
    assert "-library user" in build_hls_tcl
    assert "-ipname snn_overlay_engine" in build_hls_tcl
    assert "-version 2.0" in build_hls_tcl
    assert (
        "set packaged_ip_dir [file normalize [file join $build_dir $project_name $solution_name impl ip]]"
        in build_hls_tcl
    )
    assert "file copy -force $packaged_file $ip_out_dir" in build_hls_tcl
    assert "open_project -reset $build_dir/snn_overlay_hls" not in build_hls_tcl
    assert "export_design -format ip_catalog -output $ip_out_dir" not in build_hls_tcl


def test_hls_build_script_runs_the_testbench_before_synthesis() -> None:
    """Overlay-v1 was synthesised without anything ever executing the kernel."""
    build_hls_tcl = _hardware_file("hls", "build_hls.tcl")

    assert "add_files -tb $script_dir/snn_overlay_engine_tb.cpp" in build_hls_tcl
    assert build_hls_tcl.index("csim_design") < build_hls_tcl.index("csynth_design")


def test_vivado_build_script_discovers_exported_hls_ip() -> None:
    build_overlay_tcl = _hardware_file("vivado", "build_overlay.tcl")

    assert 'get_ipdefs -all "*:*:snn_overlay_engine:*"' in build_overlay_tcl
    assert (
        "set snn_engine_vlnv [get_property VLNV [lindex $snn_engine_ip_defs 0]]"
        in build_overlay_tcl
    )
    assert "create_bd_cell -type ip -vlnv $snn_engine_vlnv snn_engine_0" in build_overlay_tcl
    assert (
        "create_bd_cell -type ip -vlnv user.org:user:snn_overlay_engine:1.0 snn_engine_0"
        not in build_overlay_tcl
    )


def test_vivado_build_script_connects_the_engine_weight_master() -> None:
    """The v1 defect: nothing in the block design fed the weight port.

    v1 declared weights as raw BRAM ports and never attached a memory
    controller, so every weight the engine read was zero and the board could
    only ever return silence.
    """
    build_overlay_tcl = _hardware_file("vivado", "build_overlay.tcl")

    assert "CONFIG.PCW_USE_S_AXI_HP2 {1}" in build_overlay_tcl
    assert "processing_system7_0/S_AXI_HP2_ACLK" in build_overlay_tcl
    assert 'Master "/snn_engine_0/m_axi_gmem"' in build_overlay_tcl
    # And it must refuse to build a bitstream whose engine has no weight port
    # rather than shipping a second one that silently cannot read weights.
    assert "get_bd_intf_pins -quiet snn_engine_0/m_axi_gmem" in build_overlay_tcl
    assert "error" in build_overlay_tcl


def test_build_wrapper_resolves_register_offsets_from_the_hardware() -> None:
    """v1's register map was hand-written and disagreed with the bitstream."""
    build_overlay_sh = _hardware_file("scripts", "build_overlay.sh")

    assert "sync_manifest_offsets.py" in build_overlay_sh
    assert "--write" in build_overlay_sh
    assert "--check" in build_overlay_sh
    assert build_overlay_sh.index("--write") < build_overlay_sh.index("--check")
