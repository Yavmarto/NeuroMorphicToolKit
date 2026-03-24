import os
import subprocess
import argparse

MODULES = [
    "NeuroCNL", "Neurosim", "Neurosense", "Neurochip", 
    "Neurobench", "Neurohub", "Neuro-Dream-Hand"
]

ISSUE_TEMPLATE = """
### CDD-PBT Implementation Required

You are tasked with migrating this module into the **Contract-Driven and Property-Based Testing (CDD-PBT)** pipeline.

**Instructions for the Agent (Jules/Antigravity):**
1. Review the existing documentation and logic for this module.
2. Extract the strict logical/scientific boundaries and create **Contracts** (e.g., Pydantic `BaseModel`s for Python, or strict Dart classes).
3. Create mathematical invariant tests (`test_properties.py`) using `hypothesis` (or `glados` for Dart) that heavily restrict the boundaries of the code.
4. Implement or refactor the module's core logic so that it strictly adheres to these newly established contracts and passes the hypothesis properties.
5. You can execute `Gemini-dev-pipeline/cdd_validation.sh {module}` to confirm that your properties effectively restrict the logic locally before you push.

This is a CDD-PBT governance issue. Focus exclusively on adding strict invariants and ensuring the mathematical stability of the component.
"""

def main():
    parser = argparse.ArgumentParser(description="Generate CDD-PBT GitHub Issues for NMTK Modules")
    parser.add_argument("--dry-run", action="store_true", help="Print issue contents without creating them on GitHub")
    args = parser.parse_args()

    for module in MODULES:
        if not os.path.exists(module):
            print(f"Skipping module '{module}', directory not found.")
            continue
            
        title = f"CDD-PBT Migration: Implement strict Contracts and Properties for {module}"
        body = ISSUE_TEMPLATE.format(module=module)
        
        if args.dry_run:
            print(f"--- FAKE ISSUE COMMAND FOR {module} ---")
            print(f"Title: {title}")
            print("---------------------------------------")
        else:
            print(f"Submitting issue for {module}...")
            try:
                subprocess.run([
                    "gh", "issue", "create", 
                    "--title", title, 
                    "--body", body,
                    "--label", "CDD-PBT,enhancement" # Ensure labels are comma-separated and pre-exist in the repo, or omit
                ], check=True)
                print(f"✅ Successfully created issue for {module}.")
            except subprocess.CalledProcessError as e:
                print(f"❌ Failed to create issue for {module}: {e}")
            except FileNotFoundError:
                print("❌ GitHub CLI (gh) is not installed or not in PATH.")
                break

if __name__ == "__main__":
    main()
