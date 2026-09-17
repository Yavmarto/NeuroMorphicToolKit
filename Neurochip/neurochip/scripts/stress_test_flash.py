import argparse
import json
import os
import time

import serial

from neurochip.app.schemas.estimation import NetworkInput
from neurochip.app.services.flash_service import (
    FlashStatus,
    get_flash_job,
    start_flash_job,
)
from neurochip.app.services.teensy_generator import generate_teensy_project


def run_stress_test(cycles=1000, port=None):
    """Run a stress test of the flash and serial communication."""
    # Use simulation if no port provided or ttySIM requested
    if port is None or "ttySIM" in port:
        os.environ["NEUROCHIP_FLASH_SIMULATION"] = "true"
        if port is None:
            port = "/dev/ttySIM"
    else:
        os.environ["NEUROCHIP_FLASH_SIMULATION"] = "false"

    network = NetworkInput(
        num_neurons=10,
        num_synapses=20,
        neuron_model="LIF",
        populations=[{"name": "in", "size": 5}, {"name": "out", "size": 5}],
        connections=[{"pre": "in", "post": "out", "weight_count": 20}],
        weight_bit_width=8,
        network_depth=1,
    )

    results = []

    print(f"Starting stress test for {cycles} cycles on port {port}...")

    for i in range(cycles):
        start_time = time.time()

        # 1. Generate firmware
        zip_bytes = generate_teensy_project(network)

        # 2. Flash
        job = start_flash_job(zip_bytes, port)

        # 3. Wait for flash completion
        success = False
        while time.time() - start_time < 60:
            job_info = get_flash_job(job.id)
            if not job_info:
                break
            if job_info.status == FlashStatus.DONE:
                success = True
                break
            if job_info.status == FlashStatus.FAILED:
                print(f"Cycle {i + 1}: Flash failed - {job_info.error}")
                break
            time.sleep(0.1)

        duration = time.time() - start_time

        # 4. Serial verify (if not simulated)
        serial_verified = False
        if success:
            if os.getenv("NEUROCHIP_FLASH_SIMULATION") == "true":
                serial_verified = True  # Assume true for simulation
            else:
                try:
                    with serial.Serial(port, 115200, timeout=5) as ser:
                        # Wait for the boot message
                        boot_found = False
                        deadline = time.time() + 5
                        while time.time() < deadline:
                            line = ser.readline().decode(errors="ignore").strip()
                            if "NeuroChip SNN Firmware" in line:
                                boot_found = True
                                break
                        serial_verified = boot_found
                except Exception as e:
                    print(f"Cycle {i + 1}: Serial error - {e}")

        results.append(
            {
                "cycle": i + 1,
                "success": success,
                "duration": duration,
                "serial_verified": serial_verified,
            }
        )

        if (i + 1) % 10 == 0:
            print(f"Completed {i + 1}/{cycles} cycles...")

        if not success or not serial_verified:
            print(f"Cycle {i + 1} failed! Flash: {success}, Serial: {serial_verified}")

    with open("stress_results.json", "w") as f:
        json.dump(results, f, indent=2)

    success_count = sum(1 for r in results if r["success"] and r["serial_verified"])
    print(f"Stress test complete. Success rate: {success_count}/{cycles}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--cycles", type=int, default=1000)
    parser.add_argument("--port", type=str, default=None)
    args = parser.parse_args()
    run_stress_test(args.cycles, args.port)
