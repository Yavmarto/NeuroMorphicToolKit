Use exactly these two scripts:

- [build_overlay.sh](/NeuroMorphicToolKit/Neurochip/hardware/pynq_z2/scripts/build_overlay.sh)
- [stage_overlay.sh](/NeuroMorphicToolKit/Neurochip/hardware/pynq_z2/scripts/stage_overlay.sh)

**Linux host steps**

1. Put a checkout of this repo on the Linux host.
2. Open a shell and source your Xilinx tools.

```bash
source /path/to/Vivado/2022.x/settings64.sh
source /path/to/Vitis_HLS/2022.x/settings64.sh
```

3. Go to the hardware folder.

```bash
cd /path/to/NeuroMorphicToolKit/Neurochip/hardware/pynq_z2
```

4. Run the build script.

```bash
./scripts/build_overlay.sh
```

5. Expected output files after success:

```bash
/path/to/NeuroMorphicToolKit/Neurochip/hardware/pynq_z2/build/out/snn_overlay.bit
/path/to/NeuroMorphicToolKit/Neurochip/hardware/pynq_z2/build/out/snn_overlay.hwh
/path/to/NeuroMorphicToolKit/Neurochip/hardware/pynq_z2/build/out/overlay_manifest.json
```

6. Verify them:

```bash
ls -l build/out
```

7. Run the staging script on Linux.

```bash
./scripts/stage_overlay.sh
```

8. That copies the files into this Linux-checkout staging folder:

```bash
/path/to/NeuroMorphicToolKit/Neurochip/overlay_staging/pynq_z2/
```

**What to copy back to your Mac**

Copy only these 3 files from the Linux host:

- `snn_overlay.bit`
- `snn_overlay.hwh`
- `overlay_manifest.json`

Put them here on your Mac:

```bash
/NeuroMorphicToolKit/Neurochip/overlay_staging/pynq_z2/
```

**Mac verification**

Run:

```bash
ls -l /NeuroMorphicToolKit/Neurochip/overlay_staging/pynq_z2
```

You should see:

- `snn_overlay.bit`
- `snn_overlay.hwh`
- `overlay_manifest.json`

**Final step**

On your Mac, use the launcher for board `home`:

1. `Install Overlay`
2. `Check Readiness`

If `./scripts/build_overlay.sh` fails, send me the first Vivado or Vitis HLS error block and I’ll tell you the next fix directly.
