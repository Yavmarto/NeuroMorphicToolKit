/*
 * EMG Prosthetic — Teensy 4.1 Firmware
 * Phase 3 Hardware Demo #3
 *
 * Reads surface EMG from an instrumentation amplifier (or OpenBCI analog out),
 * performs on-device spike encoding via rate coding, runs a two-population
 * LIF network, and maps motor neuron output to a servo angle for prosthetic
 * hand grip control.
 *
 * Hardware:
 *   Pin A0  — EMG electrode input (from instrumentation amp or OpenBCI analog out)
 *   Pin A1  — Optional second EMG channel (e.g. antagonist muscle)
 *   Pin 9   — Servo output (PWM)
 *   Pin 13  — Built-in LED (spike indicator)
 *   Serial  — 115200 baud (raw EMG, envelope, spike count, servo angle)
 */

#include <Servo.h>
#include "snn_network.h"

/* ── Pin Definitions ────────────────────────────────────── */
static const int EMG_PIN       = A0;
static const int EMG_PIN_2     = A1;    /* optional second channel */
static const int SERVO_PIN     = 9;
static const int STATUS_LED    = 13;
static const long SERIAL_BAUD  = 115200;

/* ── EMG Processing Parameters ─────────────────────────── */
static const float EMG_BASELINE = 1.65f; /* mid-rail for 3.3 V supply */
static const float EMG_MAX      = 1.0f;  /* expected max envelope (tune to sensor) */
static const float ENV_ALPHA    = 0.05f; /* low-pass coefficient for envelope */

/* ── Servo Mapping ─────────────────────────────────────── */
static const int SERVO_MIN     = 0;     /* degrees — hand fully open */
static const int SERVO_MAX     = 180;   /* degrees — hand fully closed */

/* ── Rate Coding Parameters ────────────────────────────── */
/* spike_prob = envelope / EMG_MAX (clamped to [0,1]) */

/* ── State Variables ───────────────────────────────────── */
static float emg_envelope = 0.0f;
static unsigned long spike_count = 0;
static unsigned long window_spikes = 0;
static unsigned long window_start_ms = 0;
static const unsigned long WINDOW_MS = 100;  /* 100 ms servo update window */
static int servo_angle = 0;

Servo gripServo;

/* ── Setup ─────────────────────────────────────────────── */
void setup() {
    Serial.begin(SERIAL_BAUD);
    while (!Serial && millis() < 3000) { /* wait for USB serial */ }

    pinMode(EMG_PIN, INPUT);
    pinMode(EMG_PIN_2, INPUT);
    pinMode(STATUS_LED, OUTPUT);

    gripServo.attach(SERVO_PIN);
    gripServo.write(SERVO_MIN);

    /* Initialise LIF state to zero */
    for (int i = 0; i < TOTAL_NEURONS; i++) {
        voltage[i]    = 0.0f;
        refractory[i] = 0.0f;
        spikes[i]     = 0;
    }

    Serial.println("# EMG Prosthetic Firmware — Phase 3 Demo 3");
    Serial.println("# Columns: time_ms, raw_emg, envelope, spike, servo_angle");
    Serial.println("# ---");

    window_start_ms = millis();
    digitalWrite(STATUS_LED, LOW);
}

/* ── Main Loop (~500 Hz) ──────────────────────────────── */
void loop() {
    unsigned long now_ms = millis();

    /* 1. Read EMG analog input */
    float emg_raw = analogRead(EMG_PIN) * (3.3f / 4095.0f);

    /* 2. Rectify (remove DC offset) */
    float emg_rectified = fabsf(emg_raw - EMG_BASELINE);

    /* 3. Envelope extraction (exponential moving average) */
    emg_envelope = emg_envelope * (1.0f - ENV_ALPHA) + emg_rectified * ENV_ALPHA;

    /* 4. Rate coding: spike probability proportional to envelope */
    float spike_prob = emg_envelope / EMG_MAX;
    if (spike_prob > 1.0f) spike_prob = 1.0f;
    if (spike_prob < 0.0f) spike_prob = 0.0f;

    uint8_t spike_out = (random(1000) / 1000.0f) < spike_prob ? 1 : 0;

    if (spike_out) {
        spike_count++;
        window_spikes++;
        digitalWrite(STATUS_LED, HIGH);
    } else {
        digitalWrite(STATUS_LED, LOW);
    }

    /* 5. Feed spike as input current to LIF network */
    float input_arr[TOTAL_NEURONS];
    for (int i = 0; i < TOTAL_NEURONS; i++) input_arr[i] = 0.0f;

    /* Sensory neuron receives the spike current */
    input_arr[0] = spike_out * 2.0f;

    lif_step(0.002f, input_arr);  /* dt = 2 ms (500 Hz) */

    /* 6. Decode motor spikes → servo angle (proportional control) */
    if (now_ms - window_start_ms >= WINDOW_MS) {
        float rate = (float)window_spikes / ((float)WINDOW_MS / 1000.0f);

        /* Map spike rate to servo angle: 0 Hz → 0°, ~50 Hz → 180° */
        servo_angle = constrain((int)(rate * 3.6f), SERVO_MIN, SERVO_MAX);
        gripServo.write(servo_angle);

        window_spikes = 0;
        window_start_ms = now_ms;
    }

    /* 7. Serial output for monitoring / plotting */
    Serial.print(now_ms);
    Serial.print(',');
    Serial.print(emg_raw, 4);
    Serial.print(',');
    Serial.print(emg_envelope, 4);
    Serial.print(',');
    Serial.print(spike_out);
    Serial.print(',');
    Serial.println(servo_angle);

    /* Maintain ~500 Hz sample rate (2 ms period) */
    delay(2);
}
