// Minimal stand-in for Vitis HLS <ap_int.h>, for host builds only.
//
// This exists so `snn_overlay_engine.cpp` can be compiled and executed with a
// plain C++ compiler on any machine, without a Vitis HLS install.  Overlay-v1
// shipped a kernel whose behaviour nobody had ever executed; being able to run
// the engine on a laptop is the cheapest defence against repeating that.
//
// It is NOT on the include path of `build_hls.tcl` — under Vitis HLS the real
// headers are used.  Only the subset of the API that the engine and its
// testbench actually touch is implemented.
//
// Design note: these types deliberately expose an implicit conversion to a
// native integer and no arithmetic operators of their own.  Arithmetic
// therefore happens at native width and is truncated/sign-extended on
// assignment, which matches ap_int semantics for the widths used here and
// avoids overload ambiguity against the built-in operators.

#pragma once

#include <cstdint>

namespace ap_compat {

inline long long sign_extend(long long value, int width) {
    if (width >= 64) {
        return value;
    }
    const unsigned long long mask = (1ULL << width) - 1ULL;
    unsigned long long truncated = static_cast<unsigned long long>(value) & mask;
    const unsigned long long sign_bit = 1ULL << (width - 1);
    if (truncated & sign_bit) {
        truncated |= ~mask;
    }
    return static_cast<long long>(truncated);
}

inline unsigned long long zero_extend(unsigned long long value, int width) {
    if (width >= 64) {
        return value;
    }
    return value & ((1ULL << width) - 1ULL);
}

}  // namespace ap_compat

template <int W>
class ap_int {
  public:
    ap_int() : value_(0) {}
    ap_int(long long raw) : value_(ap_compat::sign_extend(raw, W)) {}

    operator long long() const { return value_; }

    int to_int() const { return static_cast<int>(value_); }
    long long to_int64() const { return value_; }

    ap_int& operator=(long long raw) {
        value_ = ap_compat::sign_extend(raw, W);
        return *this;
    }

    ap_int& operator+=(long long raw) { return operator=(value_ + raw); }
    ap_int& operator-=(long long raw) { return operator=(value_ - raw); }

  private:
    long long value_;
};

template <int W>
class ap_uint {
  public:
    ap_uint() : value_(0) {}
    ap_uint(unsigned long long raw)
        : value_(ap_compat::zero_extend(raw, W)) {}

    operator unsigned long long() const { return value_; }

    unsigned int to_uint() const { return static_cast<unsigned int>(value_); }
    unsigned long long to_uint64() const { return value_; }

    ap_uint& operator=(unsigned long long raw) {
        value_ = ap_compat::zero_extend(raw, W);
        return *this;
    }

    ap_uint& operator+=(unsigned long long raw) {
        return operator=(value_ + raw);
    }
    ap_uint& operator-=(unsigned long long raw) {
        return operator=(value_ - raw);
    }

  private:
    unsigned long long value_;
};
