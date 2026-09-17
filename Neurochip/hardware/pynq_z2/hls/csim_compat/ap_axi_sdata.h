// Minimal stand-in for Vitis HLS <ap_axi_sdata.h>, for host builds only.
// See csim_compat/ap_int.h for why this exists.

#pragma once

#include <ap_int.h>

template <int D, int U, int TI, int TD>
struct ap_axiu {
    ap_uint<D> data;
    ap_uint<(D + 7) / 8> keep;
    ap_uint<(D + 7) / 8> strb;
    ap_uint<(U > 0) ? U : 1> user;
    ap_uint<(TI > 0) ? TI : 1> id;
    ap_uint<(TD > 0) ? TD : 1> dest;
    ap_uint<1> last;

    ap_axiu() : data(0), keep(0), strb(0), user(0), id(0), dest(0), last(0) {}
};
