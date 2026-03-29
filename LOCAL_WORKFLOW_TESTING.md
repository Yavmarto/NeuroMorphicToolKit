# Local Workflow Testing Guide

This guide explains how to test and validate GitHub Actions workflows locally across the root repository and all submodules using the `test-workflows.sh` script, without having to commit and push changes.

## Prerequisites

To run these local checks, you will need two tools:
1. **`actionlint`**: A blazing-fast static analyzer for GitHub Actions workflows. It validates syntax, checks context availability, and flags common logical errors.
2. **`act`**: A tool for running GitHub Actions locally via Docker containers.
3. **Docker**: Required by `act` to spin up environments.

### Installation Instructions

#### 🍎 macOS
The easiest method is using [Homebrew](https://brew.sh/):
```bash
brew install actionlint act
```
*(Note: Ensure Docker Desktop is installed and running).*

#### 🐧 Linux
There are multiple ways to install the tools on Linux.

**Using curl (Pre-compiled Binaries):**
```bash
# Install actionlint
bash <(curl https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)
sudo mv actionlint /usr/local/bin/

# Install act
curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

**Using Go (If installed):**
```bash
go install github.com/rhysd/actionlint/cmd/actionlint@latest
go install github.com/nektos/act@latest
```
*(Note: Ensure Docker Engine is installed and your user is added to the `docker` group).*

#### 🪟 Windows
Since the testing script is a `.sh` file, you will need an environment capable of running Bash.

**Option 1: Windows Subsystem for Linux (WSL 2) - Recommended**
1. Install WSL 2 and your preferred Linux distribution (e.g., Ubuntu).
2. Install Docker Desktop and enable the "WSL 2 based engine" in its settings.
3. Open your WSL terminal and follow the **Linux** installation steps above.

**Option 2: Native Windows via Scoop / Winget (Using Git Bash)**
If you prefer using Git Bash to execute the shell script natively on Windows:
```powershell
# Using Scoop
scoop install actionlint act

# Using Winget (act)
winget install nektos.act
```
*(Note: You will still need Docker Desktop for Windows installed and running).*

---

## Usage

The script `test-workflows.sh` is located in the root directory. It automatically scans the root repository and all submodules for `.github/workflows/*.yml` files.

### 1. Syntax and Logic Validation (Default)
Run `actionlint` to instantly catch typos, missing variables, or invalid GitHub Expressions across the entire monorepo.
```bash
./test-workflows.sh --lint
# or simply
./test-workflows.sh
```

### 2. Dry-Run Workflows Locally
Use the `--run` flag to trigger a dry-run (`act -n`). This command parses the workflows, figures out what Docker images are needed, and prints the exact execution plan without running any side-effect tasks.
```bash
./test-workflows.sh --run
```

### 3. Run Everything
Execute both the linting and the dry-run steps sequentially.
```bash
./test-workflows.sh --all
```

---

## Running Specific Workflows to Completion

The `test-workflows.sh` script defaults to a **dry-run** for execution. This is a safety measure because firing off dozens of workflows locally across submodules in parallel can heavily consume computer resources, or accidentally publish payloads if secrets are passed.

If you have validated a workflow and want to execute it locally from end-to-end:

1. Navigate (`cd`) into the directory containing that specific repository's `.github` folder.
2. Run standard `act` commands manually:

```bash
# List all available jobs inside the workflow
act -l 

# Simulate a 'push' event
act 

# Run a specific job directly
act -j <job_name>
```

> **Warning about Secrets:**
> Local `act` runs will not have access to your live GitHub repository secrets. If your workflow requires secrets, you must create a `.secrets` file in that directory and supply it to `act`:
> `act --secret-file .secrets`
