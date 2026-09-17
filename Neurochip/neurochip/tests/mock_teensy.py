import sys
import time

import serial


def run_simulator(port):
    print(f"Starting mock Teensy simulator on {port}")
    try:
        ser = serial.Serial(port, 115200, timeout=1)
        print(f"Opened {port}")

        while True:
            if ser.in_waiting > 0:
                data = ser.read(ser.in_waiting)
                print(f"Received {len(data)} bytes")
                # Simulate some processing
                time.sleep(0.1)
                ser.write(b"ACK\n")
            time.sleep(0.01)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python mock_teensy.py <port>")
        sys.exit(1)
    run_simulator(sys.argv[1])
