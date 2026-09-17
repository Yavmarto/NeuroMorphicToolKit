# Try running pytest
import subprocess

try:
    print(
        subprocess.check_output(
            [
                "/home/jules/.pyenv/versions/3.12.13/bin/pytest",
                "--cov=neurohub",
                "--cov-report=term-missing",
                "neurohub/tests/test_all_endpoints.py",
            ],
            env={"PYTHONPATH": "/app"},
        ).decode("utf-8")
    )
except subprocess.CalledProcessError as e:
    print(e.output.decode("utf-8"))
