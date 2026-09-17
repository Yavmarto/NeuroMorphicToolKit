// Minimal stand-in for Vitis HLS <hls_stream.h>, for host builds only.
// See csim_compat/ap_int.h for why this exists.

#pragma once

#include <deque>
#include <stdexcept>
#include <string>

namespace hls {

template <typename T>
class stream {
  public:
    stream() {}
    explicit stream(const char* name) : name_(name) {}

    void write(const T& value) { queue_.push_back(value); }

    T read() {
        if (queue_.empty()) {
            throw std::runtime_error(
                "hls::stream underrun on '" + name_ +
                "': the engine read more words than the testbench wrote");
        }
        T value = queue_.front();
        queue_.pop_front();
        return value;
    }

    bool empty() const { return queue_.empty(); }
    std::size_t size() const { return queue_.size(); }

  private:
    std::deque<T> queue_;
    std::string name_ = "stream";
};

}  // namespace hls
