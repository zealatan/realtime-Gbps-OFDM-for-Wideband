`timescale 1ns/1ps

// Behavioral DFT model — Step 34, simulation only.
//
// PURPOSE: Provides a reference DFT implementation for validating the
// FFT frontend interface and generating test vectors.  Uses $cos/$sin
// real arithmetic — NOT synthesizable.
//
// DFT convention:
//   X[k] = sum_{n=0}^{N-1} x[n] * exp(-j*2*pi*k*n/N)
//   X[k]_I = sum_n (x_i[n]*cos(2*pi*k*n/N) + x_q[n]*sin(2*pi*k*n/N))
//   X[k]_Q = sum_n (-x_i[n]*sin(2*pi*k*n/N) + x_q[n]*cos(2*pi*k*n/N))
//
// Scaling: unnormalized (X[k] has amplitude N for a unit-amplitude input).
//
// Bin order: natural order.
//   k=0   = DC
//   k=1..FFT_LEN/2-1  = positive frequencies
//   k=FFT_LEN/2..FFT_LEN-1 = negative frequencies
//   No fftshift applied.
//
// Quantization: round-to-nearest, saturate to signed IQ_WIDTH bits.
//
// Usage:
//   Drive compute=1 after loading in_i/in_q; results appear in out_i/out_q
//   after one delta step (combinatorial on posedge compute).
//   Toggle compute low then high again for a new computation.

module fft256_behavioral_model #(
    parameter integer FFT_LEN  = 256,
    parameter integer IQ_WIDTH = 16
)(
    input  logic signed [IQ_WIDTH-1:0] in_i  [0:FFT_LEN-1],
    input  logic signed [IQ_WIDTH-1:0] in_q  [0:FFT_LEN-1],
    output logic signed [IQ_WIDTH-1:0] out_i [0:FFT_LEN-1],
    output logic signed [IQ_WIDTH-1:0] out_q [0:FFT_LEN-1],
    input  logic                       compute
);

// synthesis translate_off

    real     _pi2;
    real     _si, _sq, _ang, _ri, _rq;
    integer  _k, _n;
    integer  _sat_lo, _sat_hi;
    integer  _ival, _qval;

    initial begin
        for (_k = 0; _k < FFT_LEN; _k++) begin
            out_i[_k] = '0;
            out_q[_k] = '0;
        end
        _pi2    = 6.283185307179586;
        _sat_hi = (1 << (IQ_WIDTH-1)) - 1;   //  32767 for 16-bit
        _sat_lo = -(1 << (IQ_WIDTH-1));        // -32768 for 16-bit
    end

    always @(posedge compute) begin
        for (_k = 0; _k < FFT_LEN; _k++) begin
            _si = 0.0;
            _sq = 0.0;
            for (_n = 0; _n < FFT_LEN; _n++) begin
                _ang = _pi2 * _k * _n / FFT_LEN;
                _si = _si + $itor($signed(in_i[_n])) * $cos(_ang)
                          + $itor($signed(in_q[_n])) * $sin(_ang);
                _sq = _sq - $itor($signed(in_i[_n])) * $sin(_ang)
                          + $itor($signed(in_q[_n])) * $cos(_ang);
            end
            // Round to nearest integer
            _ri = (_si >= 0.0) ? (_si + 0.5) : (_si - 0.5);
            _rq = (_sq >= 0.0) ? (_sq + 0.5) : (_sq - 0.5);
            // Saturate to IQ_WIDTH
            _ival = $rtoi(_ri);
            _qval = $rtoi(_rq);
            if (_ival > _sat_hi) _ival = _sat_hi;
            if (_ival < _sat_lo) _ival = _sat_lo;
            if (_qval > _sat_hi) _qval = _sat_hi;
            if (_qval < _sat_lo) _qval = _sat_lo;
            out_i[_k] = IQ_WIDTH'(_ival);
            out_q[_k] = IQ_WIDTH'(_qval);
        end
    end

// synthesis translate_on

endmodule
