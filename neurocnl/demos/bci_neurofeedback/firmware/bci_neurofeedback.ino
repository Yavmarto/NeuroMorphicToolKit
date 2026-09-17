/*
 * BCI Neurofeedback — Teensy 4.1 Firmware
 * Phase 3 Hardware Demo #5
 *
 * Reads EEG analog input, extracts alpha-band envelope,
 * runs on-device spike encoding + LIF neuron step,
 * and drives visual (LED PWM) feedback.
 *
 * Hardware:
 *   Pin A0  — EEG analog input (from OpenBCI analog out or instrumentation amp)
 *   Pin 9   — LED brightness (PWM) for visual feedback
 *   Pin 13  — Built-in LED state indicator
 *   Serial  — 115200 baud (raw EEG, filtered alpha, spike count, feedback)
 */

#include "snn_network.h"

/* ── Pin Definitions ────────────────────────────────────── */
static const int EEG_PIN       = A0;
static const int FEEDBACK_PIN  = 9;   /* PWM-capable for LED brightness */
static const int STATUS_LED    = 13;  /* built-in LED */
static const long SERIAL_BAUD  = 115200;

/* ── Alpha Band-Pass Filter (simple IIR, ~10 Hz centre) ── */
/* Two-pole IIR coefficients targeting 8-12 Hz at ~200 Hz sample rate.
 * y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
 * Approximate 2nd-order Butterworth bandpass centred at 10 Hz.          */
static const float BPF_B0 =  0.0201f;
static const float BPF_B1 =  0.0f;
static const float BPF_B2 = -0.0201f;
static const float BPF_A1 = -1.5610f;
static const float BPF_A2 =  0.9598f;

static float bpf_x1 = 0.0f, bpf_x2 = 0.0f;
static float bpf_y1 = 0.0f, bpf_y2 = 0.0f;

float bandpass_step(float x) {
    float y = BPF_B0 * x + BPF_B1 * bpf_x1 + BPF_B2 * bpf_x2
            - BPF_A1 * bpf_y1 - BPF_A2 * bpf_y2;
    bpf_x2 = bpf_x1;  bpf_x1 = x;
    bpf_y2 = bpf_y1;  bpf_y1 = y;
    return y;
}

/* ── Envelope Extraction (exponential moving average) ──── */
static const float ENV_ATTACK  = 0.05f;  /* fast rise  */
static const float ENV_RELEASE = 0.005f; /* slow decay */
static float envelope = 0.0f;

float envelope_step(float rectified) {
    float alpha_coeff = (rectified > envelope) ? ENV_ATTACK : ENV_RELEASE;
    envelope += alpha_coeff * (rectified - envelope);
    return envelope;
}

/* ── Delta Modulation Spike Encoder ────────────────────── */
static const float DELTA_THRESHOLD = 0.05f;
static float delta_ref = 0.0f;
static uint8_t spike_out = 0;

uint8_t delta_encode_step(float value) {
    if (fabsf(value - delta_ref) >= DELTA_THRESHOLD) {
        delta_ref = value;
        return 1;
    }
    return 0;
}

/* ── Feedback State ────────────────────────────────────── */
static unsigned long spike_count = 0;
static unsigned long window_spikes = 0;
static unsigned long window_start_ms = 0;
static const unsigned long WINDOW_MS = 500;  /* 0.5 s feedback window */
static int feedback_level = 0;               /* 0-255 PWM */

/* ── Setup ─────────────────────────────────────────────── */
void setup() {
    Serial.begin(SERIAL_BAUD);
    while (!Serial && millis() < 3000) { /* wait for USB serial */ }

    pinMode(EEG_PIN, INPUT);
    pinMode(FEEDBACK_PIN, OUTPUT);
    pinMode(STATUS_LED, OUTPUT);

    analogWriteResolution(8);

    /* Print header */
    Serial.println("# BCI Neurofeedback Firmware — Phase 3 Demo 5");
    Serial.println("# Columns: time_ms, raw_eeg, alpha_filtered, envelope, spike, feedback");
    Serial.println("# ---");

    window_start_ms = millis();
    digitalWrite(STATUS_LED, HIGH);  /* indicate running */
}

/* ── Main Loop (~200 Hz) ──────────────────────────────── */
void loop() {
    unsigned long now_ms = millis();

    /* 1. Read raw EEG (10-bit ADC → float, centred at 0) */
    int raw_adc = analogRead(EEG_PIN);
    float raw_eeg = (raw_adc - 512) / 512.0f;  /* normalise to ±1 */

    /* 2. Alpha bandpass filter */
    float alpha_filtered = bandpass_step(raw_eeg);

    /* 3. Envelope extraction (rectify + smooth) */
    float env = envelope_step(fabsf(alpha_filtered));

    /* 4. Delta-modulation spike encoding */
    spike_out = delta_encode_step(env);
    if (spike_out) {
        spike_count++;
        window_spikes++;
    }

    /* 5. Feed spike to LIF neuron (from snn_network.h) */
    float input_arr[TOTAL_NEURONS];
    for (int i = 0; i < TOTAL_NEURONS; i++) input_arr[i] = 0.0f;
    input_arr[SENSORY_NEURON_INDEX] = spike_out * 2.0f;  /* scale spike current */

    lif_step(0.005f, input_arr);  /* dt = 5 ms (200 Hz) */

    /* 6. Count motor spikes in current window */
    /* Motor spikes drive feedback intensity */

    /* 7. Update feedback every WINDOW_MS */
    if (now_ms - window_start_ms >= WINDOW_MS) {
        /* Map window spike count to LED brightness (0-255) */
        float rate = (float)window_spikes / ((float)WINDOW_MS / 1000.0f);
        feedback_level = constrain((int)(rate * 2.5f), 0, 255);

        analogWrite(FEEDBACK_PIN, feedback_level);

        /* Blink status LED with feedback level */
        digitalWrite(STATUS_LED, feedback_level > 128 ? HIGH : LOW);

        window_spikes = 0;
        window_start_ms = now_ms;
    }

    /* 8. Serial output */
    Serial.print(now_ms);
    Serial.print(',');
    Serial.print(raw_eeg, 4);
    Serial.print(',');
    Serial.print(alpha_filtered, 4);
    Serial.print(',');
    Serial.print(env, 4);
    Serial.print(',');
    Serial.print(spike_out);
    Serial.print(',');
    Serial.println(feedback_level);

    /* Maintain ~200 Hz sample rate (5 ms period) */
    delay(5);
}
