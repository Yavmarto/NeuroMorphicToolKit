#!/bin/bash
set -e
printf "VAL=%s\n" "$(cat non_existent_file 2> err.log)"
echo "Finished"
cat err.log
