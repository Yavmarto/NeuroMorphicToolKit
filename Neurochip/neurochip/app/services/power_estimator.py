"""Power and latency estimation service."""

import json
import os

from neurochip.contracts.hardware_contracts import HardwareProfile

from ..schemas.estimation import LatencyEstimate, NetworkInput, PowerEstimate


def _load_target(target_id: str) -> HardwareProfile:
    targets_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "targets")
    filepath = os.path.join(targets_dir, f"{target_id}.json")
    with open(filepath) as f:
        return HardwareProfile(**json.load(f))


def estimate_power(network: NetworkInput, target_id: str) -> PowerEstimate:
    """
    Estimate energy per inference based on spike activity and target specs.

    In production, this would wrap neurodreamhand's power_profiler for
    more accurate activity-based estimates.
    """
    target = _load_target(target_id)

    per_population = []
    total_energy = 0.0

    for pop in network.populations:
        # Estimate average spikes per inference per neuron
        # Typical SNN: ~10% of neurons spike per timestep
        avg_spike_rate = 0.10
        spikes_per_inference = int(pop["size"] * avg_spike_rate * network.network_depth)

        # Find synapses originating from this population
        pop_synapses = sum(
            c["weight_count"] for c in network.connections if c["pre"] == pop["name"]
        )

        # Energy calculation: spikes * fan-out * pJ/spike-op
        energy = (
            spikes_per_inference * (pop_synapses / max(pop["size"], 1)) * target.pj_per_spike_op
        )
        total_energy += energy

        per_population.append(
            {
                "name": pop["name"],
                "energy_pj": round(energy, 2),
                "spike_count": spikes_per_inference,
            }
        )

    exceeds = total_energy > (target.power_envelope_mw * 1e9)  # convert mW to pJ/s rough

    notes = "Estimated — measure on real hardware for production."
    if exceeds:
        notes = (
            f"WARNING: Estimated energy may exceed {target.name}'s "
            f"{target.power_envelope_mw} mW envelope. " + notes
        )

    return PowerEstimate(
        target_id=target_id,
        total_energy_pj=round(total_energy, 2),
        per_population_breakdown=per_population,
        power_envelope_mw=target.power_envelope_mw,
        exceeds_envelope=exceeds,
        notes=notes,
        method="coarse_heuristic",
        is_estimate=True,
        accuracy_note=(
            "Power estimate uses target-class energy-per-op constants. Actual consumption "
            "depends on network activity and clock settings."
        ),
    )


def estimate_latency(network: NetworkInput, target_id: str) -> LatencyEstimate:
    """
    Estimate inference latency based on network depth and target clock speed.
    """
    target = _load_target(target_id)

    depth = network.network_depth

    if target.clock_speed_mhz > 0:
        # Time per timestep = 1 / clock_speed (in microseconds)
        us_per_step = 1.0 / target.clock_speed_mhz
    else:
        # Asynchronous chips (Loihi): use estimated per-step latency
        # ~1 us per timestep is typical for Loihi
        us_per_step = 1.0

    # Inter-core communication overhead (estimated)
    # More neurons = more likely to span multiple cores
    num_cores_needed = max(1, network.num_neurons // 1024)
    inter_core_us = 0.5 * max(0, num_cores_needed - 1)  # 0.5 us per core hop

    best_case = depth * us_per_step
    typical = depth * us_per_step + inter_core_us
    worst_case = depth * us_per_step * 1.5 + inter_core_us * 2  # contention factor

    return LatencyEstimate(
        target_id=target_id,
        network_depth=depth,
        best_case_us=round(best_case, 4),
        typical_us=round(typical, 4),
        worst_case_us=round(worst_case, 4),
        clock_speed_mhz=target.clock_speed_mhz,
        inter_core_overhead_us=round(inter_core_us, 4),
    )
