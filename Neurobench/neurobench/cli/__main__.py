import json
import sys

import click

from app.schemas.results import RegressionCriteria, RegressionThreshold
from app.services.benchmark_loader import benchmark_loader
from app.services.benchmark_runner import benchmark_runner
from app.services.diff_engine import diff_engine


@click.group()
def cli() -> None:
    """NeuroBench CLI — Benchmark tool for SNN performance."""
    pass


@cli.command()
@click.argument("benchmark_id")
@click.option(
    "--network",
    required=True,
    type=click.Path(exists=True),
    help="Path to the .cnl network specification file.",
)
@click.option(
    "--baseline",
    type=click.Path(exists=True),
    help="Path to a baseline result JSON to compare against.",
)
@click.option("--fail-on-regression", is_flag=True, help="Fail the build if performance regresses.")
@click.option("--threshold", type=float, default=1.0, help="Regression tolerance % (default: 1.0).")
@click.option(
    "--criteria-json",
    type=str,
    help="JSON string for complex RegressionCriteria (overrides --threshold).",
)
@click.option("--seed", type=int, help="Seed for reproducibility.")
def run(
    benchmark_id: str,
    network: str,
    baseline: str | None,
    fail_on_regression: bool,
    threshold: float,
    criteria_json: str | None,
    seed: int | None,
) -> None:
    """Run a specific benchmark against a network."""
    try:
        result = benchmark_runner.run_benchmark(benchmark_id, network, seed=seed)
        click.echo(json.dumps(result.model_dump(), indent=2))

        if baseline:
            from contracts import BenchmarkResult

            with open(baseline) as f:
                base_data = json.load(f)
                baseline_result = BenchmarkResult(**base_data)

            benchmark_def = benchmark_loader.get(benchmark_id)
            if not benchmark_def:
                click.echo(f"Error: Benchmark definition '{benchmark_id}' not found.", err=True)
                sys.exit(1)

            if criteria_json:
                criteria = RegressionCriteria(**json.loads(criteria_json))
            else:
                higher_is_better = benchmark_def.scoring.higher_is_better
                criteria = RegressionCriteria(
                    default_threshold=RegressionThreshold(
                        tolerance=threshold,
                        comparison_direction="higher_is_better"
                        if higher_is_better
                        else "lower_is_better",
                    )
                )

            diff = diff_engine.compute_diff(baseline_result, result, criteria=criteria)

            if diff.has_regression:
                click.echo("\n--- REGRESSION DETECTED ---", err=True)
                for metric in diff.metrics:
                    if metric.threshold_violated:
                        click.echo(
                            f"Metric '{metric.name}' regressed: {metric.baseline_value} -> "
                            f"{metric.current_value} ({metric.delta_pct:+.2f}%)",
                            err=True,
                        )
                if fail_on_regression:
                    sys.exit(1)
            else:
                click.echo("\nNo regressions detected.")

    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


if __name__ == "__main__":
    cli()
