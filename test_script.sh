#!/bin/bash
export FOO="bar"
OUT="$(python3 - <<'PY'
import os
print(os.environ["FOO"])
PY
)"
echo "RESULT: $OUT"
