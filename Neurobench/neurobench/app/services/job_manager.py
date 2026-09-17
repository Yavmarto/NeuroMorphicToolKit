import uuid
from concurrent.futures import Future, ThreadPoolExecutor
from typing import Any

from app.schemas.benchmarks import BenchmarkJob, JobStatus
from app.services.benchmark_runner import benchmark_runner
from app.services.clock import utc_now_iso
from app.services.result_store import result_store


class JobManager:
    """Manages asynchronous benchmark execution jobs."""

    def __init__(self, max_workers: int = 4) -> None:
        """Initialize the JobManager with a thread pool.

        Args:
            max_workers (int): Maximum number of concurrent benchmark jobs.
        """
        self.executor = ThreadPoolExecutor(max_workers=max_workers)
        self.active_jobs: dict[str, Future[Any]] = {}

    def submit_job(
        self,
        benchmark_id: str,
        network_path: str | None = None,
        network_content: str | None = None,
        params: dict[str, Any] | None = None,
        seed: int | None = None,
        target: str = "simulation",
    ) -> str:
        """Submit a new benchmark job for asynchronous execution.

        Args:
            benchmark_id (str): ID of the benchmark to run.
            network_path (str | None): Server-side file path to a .cnl spec.
            network_content (str | None): Inline CNL spec content (CNL Studio integration).
            params (dict[str, Any] | None): Execution parameters.
            seed (int | None): Random seed.
            target (str): Execution target (simulation, neurosim, neurochip).

        Returns:
            str: The unique job ID.
        """
        job_id = f"job_{uuid.uuid4().hex[:8]}"
        now = utc_now_iso()
        stored_path = network_path if network_path else "<inline>"

        job = BenchmarkJob(
            id=job_id,
            benchmark_id=benchmark_id,
            network_path=stored_path,
            params=params,
            seed=seed,
            status=JobStatus.PENDING,
            created_at=now,
            updated_at=now,
        )

        result_store.save_job(job)

        future = self.executor.submit(
            self._execute_job,
            job_id,
            benchmark_id,
            network_path,
            network_content,
            params,
            seed,
            target,
        )
        self.active_jobs[job_id] = future

        return job_id

    def get_job_status(self, job_id: str) -> BenchmarkJob:
        """Retrieve the current status of a benchmark job.

        Args:
            job_id (str): The ID of the job.

        Returns:
            BenchmarkJob: The job object with its current status.

        Raises:
            ValueError: If the job ID is not found.
        """
        job = result_store.get_job(job_id)
        if not job:
            raise ValueError(f"Job '{job_id}' not found.")
        return job

    def cancel_job(self, job_id: str) -> bool:
        """Attempt to cancel a pending or running job.

        Args:
            job_id (str): The ID of the job to cancel.

        Returns:
            bool: True if the job was successfully cancelled, False otherwise.
        """
        job = result_store.get_job(job_id)
        if not job:
            return False

        if job.status in (JobStatus.COMPLETED, JobStatus.FAILED, JobStatus.CANCELLED):
            return False

        future = self.active_jobs.get(job_id)
        if future:
            # Note: ThreadPoolExecutor cannot cancel running tasks, only pending ones.
            # But we can update the status to CANCELLED.
            cancelled = future.cancel()
            if cancelled:
                self._update_job_status(job_id, JobStatus.CANCELLED)
                return True

        # If it's already running, we just mark it as cancelled.
        # The _execute_job will see the status changed if we check it (optional).
        self._update_job_status(job_id, JobStatus.CANCELLED)
        return True

    def _execute_job(
        self,
        job_id: str,
        benchmark_id: str,
        network_path: str | None = None,
        network_content: str | None = None,
        params: dict[str, Any] | None = None,
        seed: int | None = None,
        target: str = "simulation",
    ) -> None:
        """Internal method to execute a benchmark and update its status."""
        job = result_store.get_job(job_id)
        if not job or job.status == JobStatus.CANCELLED:
            return

        self._update_job_status(job_id, JobStatus.RUNNING)

        try:
            result = benchmark_runner.run_benchmark(
                benchmark_id=benchmark_id,
                network_path=network_path,
                network_content=network_content,
                params=params,
                seed=seed,
                target=target,
            )
            self._update_job_status(job_id, JobStatus.COMPLETED, result_id=result.id)
        except Exception as e:
            # Check if it was cancelled during execution
            current_job = result_store.get_job(job_id)
            if current_job and current_job.status != JobStatus.CANCELLED:
                self._update_job_status(job_id, JobStatus.FAILED, error=str(e))
        finally:
            if job_id in self.active_jobs:
                del self.active_jobs[job_id]

    def _update_job_status(
        self,
        job_id: str,
        status: JobStatus,
        result_id: str | None = None,
        error: str | None = None,
    ) -> None:
        """Helper to update job status in the database."""
        job = result_store.get_job(job_id)
        if job:
            job.status = status
            if result_id:
                job.result_id = result_id
            if error:
                job.error = error
            job.updated_at = utc_now_iso()
            result_store.save_job(job)


# Singleton instance
job_manager = JobManager()
