#!/bin/bash
set -e
STATUS_JSON="$(python3 -c "import sys; sys.exit(1)" 2> err.log)"
echo "Finished"
