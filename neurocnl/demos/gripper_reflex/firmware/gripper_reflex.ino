/**
 * Gripper Reflex — Phase 3 Hardware Demo #1
 *
 * Teensy 4.1 firmware for a spiking-neural-network-driven gripper.
 *
 * Wiring:
 *   Pin A0 ← FSR 402 (voltage divider with 10kΩ to GND)
 *   Pin 9  → Servo signal (PWM)
 *
 * Pipeline: FSR analog read → normalise [0,1] → LIF SNN → servo angle
 * Loop rate: ~500 Hz (2 ms per step, matching Nengo dt = 0.002)
 */

#include <Servo.h>
#include "snn_network.h"

/* ── Pin assignments ──────────────────────────────────── */
static const int FSR_PIN   = A0;
static const int SERVO_PIN = 9;

/* ── Timing ───────────────────────────────────────────── */
static const float DT_S           = 0.002f;   /* 2 ms timestep */
static const unsigned long DT_US  = 2000UL;   /* 2 ms in microseconds */

/* ── Servo limits ─────────────────────────────────────── */
static const int SERVO_MIN_DEG =  10;   /* minimum grip angle (open) */
static const int SERVO_MAX_DEG = 160;   /* maximum grip angle (closed) */

/* ── Spike-to-angle smoothing (exponential moving average) */
static const float EMA_ALPHA = 0.05f;

Servo gripper;
static float ema_angle = 0.0f;

void setup() {
    Serial.begin(115200);
    while (!Serial && millis() < 2000) { /* wait for USB serial */ }

    analogReadResolution(12);  /* Teensy 4.1: 12-bit ADC (0–4095) */
    pinMode(FSR_PIN, INPUT);

    gripper.attach(SERVO_PIN);
    gripper.write(SERVO_MIN_DEG);

    /* Zero SNN state */
    for (int i = 0; i < TOTAL_NEURONS; i++) {
        voltage[i]    = 0.0f;
        refractory[i] = 0.0f;
        spikes[i]     = 0;
    }

    Serial.println("Gripper Reflex — SNN ready");
    Serial.print("Populations: ");
    Serial.println(NUM_POPULATIONS);
    Serial.print("Total neurons: ");
    Serial.println(TOTAL_NEURONS);
}

void loop() {
    unsigned long t0 = micros();

    /* ── 1. Read FSR and normalise to [0, 1] ─────────── */
    int raw = analogRead(FSR_PIN);
    float fsr = (float)raw / 4095.0f;

    /* ── 2. Build input current array ─────────────────── */
    float input[TOTAL_NEURONS];
    for (int i = 0; i < TOTAL_NEURONS; i++) {
        input[i] = 0.0f;
    }

    /* Drive sensory neurons with FSR value scaled by connection weight */
    for (int i = SENSORY_NEURON_INDEX;
         i < SENSORY_NEURON_INDEX + SENSORY_NEURON_N_NEURONS; i++) {
        input[i] = fsr * W_SENSORY_NEURON_TO_MOTOR_NEURON;
    }

    /* ── 3. Step the LIF network ──────────────────────── */
    lif_step(DT_S, input);

    /* ── 4. Count motor neuron spikes ─────────────────── */
    int motor_spikes = 0;
    for (int i = MOTOR_NEURON_INDEX;
         i < MOTOR_NEURON_INDEX + MOTOR_NEURON_N_NEURONS; i++) {
        motor_spikes += spikes[i];
    }

    /* ── 5. Map spike count → servo angle ─────────────── */
    float spike_ratio = (float)motor_spikes / (float)MOTOR_NEURON_N_NEURONS;
    float target_angle = SERVO_MIN_DEG
        + spike_ratio * (SERVO_MAX_DEG - SERVO_MIN_DEG);

    /* Exponential moving average for smooth servo control */
    ema_angle = EMA_ALPHA * target_angle + (1.0f - EMA_ALPHA) * ema_angle;
    int servo_cmd = constrain((int)(ema_angle + 0.5f),
                              SERVO_MIN_DEG, SERVO_MAX_DEG);
    gripper.write(servo_cmd);

    /* ── 6. Debug output (every ~100 ms = 50 steps) ───── */
    static int step_count = 0;
    if (++step_count >= 50) {
        step_count = 0;
        Serial.print("FSR=");
        Serial.print(fsr, 3);
        Serial.print(" spk=");
        Serial.print(motor_spikes);
        Serial.print(" ang=");
        Serial.println(servo_cmd);
    }

    /* ── 7. Maintain ~500 Hz loop rate ────────────────── */
    unsigned long elapsed = micros() - t0;
    if (elapsed < DT_US) {
        delayMicroseconds(DT_US - elapsed);
    }
}
