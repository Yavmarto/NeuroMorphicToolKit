#!/bin/bash
TEST_FILE=$1
VIDEO_NAME="test_run_$(date +%s).mov"
echo "Starting macOS screen record..."
screencapture -v ./$VIDEO_NAME &
RECORD_PID=$!
echo "Running Flutter test on macOS..."
flutter test -d macos $TEST_FILE
echo "Stopping screen record..."
kill -2 $RECORD_PID
sleep 2
echo "Done! Video saved locally as $VIDEO_NAME"
