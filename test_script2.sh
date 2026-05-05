#!/bin/bash
f() {
    export UNDEFINED_VAR
    python3 -c "import os; print('x' in os.environ, os.environ.get('UNDEFINED_VAR'))"
}
f
