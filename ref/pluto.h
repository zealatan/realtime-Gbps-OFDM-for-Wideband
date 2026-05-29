#ifndef PLUTO_H
#define PLUTO_H

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include <complex.h>
#include <stdbool.h>
#include <signal.h>
#include <string.h>
#include <iio.h>
#include <ad9361.h>
#include <fcntl.h> // open function
#include <unistd.h> // close function
#include <pthread.h>
#include <fftw3.h>
#include <assert.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define FILE_DATA_BITS "Data_Bits.txt"
#define FILE_PILOT_BITS "Pilot_Bits.txt"
#define FILE_CONTROL_BITS "Control_Bits.txt"
#define FILE_ESTIMATION_BITS "Estimation_Bits.txt"


/* helper macros */
#define MHZ(x) ((long long)(x*1000000.0 + .5))
#define GHZ(x) ((long long)(x*1000000000.0 + .5))

#define IIO_ENSURE(expr) { \
	if (!(expr)) { \
		(void) fprintf(stderr, "assertion failed (%s:%d)\n", __FILE__, __LINE__); \
		(void) abort(); \
	} \
}

#define PI 3.1415926535
#define SQRT_OF_2 1.41421356237
    
#define SCALE_BPSK 1.0    
#define SCALE_QPSK 0.707106781186547
#define SCALE_16QAM 0.316227766016838
#define SCALE_64QAM 0.154303349962092 
#define SCALE_256QAM 0.076696498884737

#define PSS_RANGE 3
#define SSS_RANGE 336

#define NUM_SYN_BLOCKS 2		//number of synchronization blocks in a slot
#define NUM_EST_BLOCKS 0		//number of estimation blocks in a slot
#define NUM_CTRL_BLOCKS 0		//number of control blocks in a slot
#define NUM_DATA_BLOCKS 5	//total number of blocks in a slot

#define NSC 256         // Number of subcarriers
#define CP_LEN 32       // CP length in samples (subcarriers? or symbols?), the same for all numerologies

enum modulation {
    BPSK = 1, QPSK = 2, QAM16 = 4, QAM64 = 6, QAM256 = 8
};

typedef enum {ZF, MRC, MMSE} equalizerType;

typedef float real;
typedef struct{
    real Re; 
    real Im;
} cmplx;

//=========================================== Signal Processing===========================================

struct signal_processing_structure {	//Parameters for Signal Processing 

	float* tx_data_bits;
	unsigned int tx_bitsPerSymbol;
	size_t tx_data_bits_per_block;

	float* rx_data_bits;
	unsigned int rx_bitsPerSymbol;
	size_t rx_data_bits_per_block;

	size_t num_data_subcarrier;
	
	// Pilots index and value generation
	float* pilot_bits;
    size_t numPilots;         // set number of pilot carriers 
    unsigned int bitsPerSymbolPilot;
	size_t pilot_bits_per_block;
	size_t symbols_per_block;

	 // data and pilot subcarriers' indexes
    int* dataIndx;
    int* pltIndx;

	// pilot sequence
    float* pltI;
    float* pltQ;
	
	size_t symbols_per_slot;
	
	size_t burst_len;
	size_t total_slot_len;	//the number of smaples in a TX slot (burst + sync blocks + data blocks)
	float* tx_I;	//samples to put to Pluto TX buffer
	float* tx_Q;

	float* rx_I;
	float* rx_Q;

	float BER;
	float SER;	
 
    // m and gold sequence initialization
    size_t seqLen;           			// the length of m and gold sequences
    size_t syncSigStartIndex; 			// first subcarrier to put m and gold sequence
	unsigned int Nid_1;					// Cell ID 1
	unsigned int Nid_2;              	// Cell ID 2
	unsigned int bitsPerSymbolPreamble;
	//upsampled m and gold sequence
	float* mUI;
    float* mUQ;
    float* goldUI;
    float* goldUQ;

	size_t slot_cnt;
	float PSSGain;
	long long samplingFreq;

	fftwf_plan plan_ifft;
	fftwf_plan plan_fft;
	fftwf_plan plan_ifft_pilot;
	fftwf_plan plan_fft_corr;
	fftwf_plan plan_ifft_corr;

	char file_channel_IQ_name[100];
    char file_channel_Complex_name[100];
    char file_Constellation_name[100];
};

typedef struct signal_processing_structure signal_processing_structure;
typedef signal_processing_structure* sig_pro_ptr_t;

//---------------- Common ------------------
sig_pro_ptr_t signal_processing_parameters_init(void);
void signal_processing_parameters_free(sig_pro_ptr_t signal_process);
void m_seq(float* preambleI, float* preambleQ, int len, int bitsPerSymbolPreamble, int Nid_2);
void gold_seq(float* preambleI, float* preambleQ, int len, int bitsPerSymbolPreamble, int Nid_1, int Nid_2);
void idft(float* inI, float* inQ, int len, float* outI, float* outQ);
void fft_with_rearrange( float complex* inCmplx, float *outI, float *outQ, int len, fftwf_plan plan_forward );
void fft_without_rearrange( float complex* inCmplx, float *outI, float *outQ, int len, fftwf_plan plan_forward );
void ifft_new( float complex* inCmplx, float *outI, float *outQ, int len, fftwf_plan plan_backward );
void rearrange_spectrum(long long len, float complex* mag);
void ifft(cmplx *v, int len, cmplx *tmp );
void fft( cmplx *v, int len, cmplx *tmp );

//---------------- Transmitter ------------------
void generate_transmit_slot(sig_pro_ptr_t signal_process);
void insert_cp(int signalLen, int giLen, float* txI, float* txQ);
void generate_symbol_bpsk(float* bits, float* symbol_I, float* symbol_Q);
void generate_symbol_qpsk(float* bits, float* symbol_I, float* symbol_Q);
void generate_symbol_16qam(float* bits, float* symbol_I, float* symbol_Q);
void generate_symbol_64qam(float* bits, float* symbol_I, float* symbol_Q);
void generate_symbol_256qam(float* bits, float* symbol_I, float* symbol_Q);
int generate_asymbol(float* bits, int len, float* symbol_I, float* symbol_Q);
int generate_symbols(float* txBits, int bitsPerSymbol, int howManySymbols, 
        float* txSymI, float* txSymQ);
void insert_cp(int signalLen, int giLen, float* txI, float* txQ);
void store_in_aslot(float* txI, float* txQ, int signalLen, float* slotI, float* slotQ);
void get_data_pilot_indexes(int dataIndx[], int pltIndx[], int numCarriers, int numPilots, int lastPilot);
void insert_symbols_fdm(float frmI[], float frmQ[], float symI[], float symQ[], int symIndx[], int symLen);
void RMS_normalize_signal(size_t len, float* inI, float* inQ);
void get_pilot_indexes_for_fft_interpolation_toan(int dataIndx[], int pltIndx[], int numCarriers, int numPilots);

//---------------- Receiver ------------------
bool process_received_slot(sig_pro_ptr_t signal_process);
int synchronization(float* rxI, float* rxQ, int rxLen, int symbols_per_slot, int burst_len, 
						float* mUI, float* mUQ, float* goldUI, float* goldUQ, int syncSigStartIndex, 
						int seqLen, int bitsPerSymbolPreamble, int Nid_2, long long samplingFreq, fftwf_plan plan_fft, 
						fftwf_plan plan_fft_corr, fftwf_plan plan_ifft_corr);
int frame_detector(float* freqOffsetDataI, float* freqOffsetDataQ, int len, int wndLen, float threshold);
void apply_carrier_freq_offset(float freq_offset, float phase, int freq_sampling, int startPoint, int lenIN, 
								float* outFadedI, float* outFadedQ);
int find_max_index(float* maxValuBuffSSS, int len);
int carrierFreqOffsetEstMeyr(float* rxI ,float* rxQ, float* mUI, float* mUQ, float* goldUI, float* goldUQ, int slotStartIndex, 
								fftwf_plan plan_fft, fftwf_plan plan_fft_corr, fftwf_plan plan_ifft_corr);
void fft_correlation_Meyr( float * inI1, float* inQ1, float * inI2, float* inQ2, float* outI, float* outQ, 
                        fftwf_plan plan_forward, fftwf_plan plan_backward );
int VanDeBeekAutoCorrelation(float* rxI, float* rxQ, int frameStart, float* autoCorrOutI, float* autoCorrOutQ);
void auto_corr(float* inI, float* inQ, float* outI, float* outQ, int nFFT, int cpLen, float* normalizedValue);
int find_peak_index(float* preambleConvI, float* preambleConvQ, int preambleConvLen, float* peakValue);
float agc_flex(float* recDI, float* recDQ, int rxDLen, int blockLen, int slotIndex, 
        float previousGain, float alpha);
int fde(equalizerType equalizer, float* Hi, float* Hq,
        float* RXSigI, float* RXSigQ, int len, float* eqScale);
void decode_bpsk(float* recSymI, float* recSymQ, float* recBit);
void decode_qpsk(float* recSymI, float* recSymQ, float* recBits);
void decode_16qam(float* recSymI, float* recSymQ, float* recBits);
void decode_64qam(float* recSymI, float* recSymQ, float* recBits);
void decode256qam(float* recSymI, float* recSymQ, float* recBits);
int decode_asymbol(float* recSymI, float* recSymQ, float* recBits, int bitsPerSymbol);
int decode_symbols(float* rxSymI, float* rxSymQ, int howManySymbols, int bitsPerSymbol, float* rxBits);
void ch_estimation_fdm(float Hi[], float Hq[], float rxSigI[], float rxSigQ[], float pltI[], float pltQ[], int pltIndx[], int pltLen);
void interp_linear(float Hi[], float Hq[], int pltIndx[], int numCarriers, int numPilots);
void interp_quadratic(float Hi[], float Hq[], int pltIndx[], int numCarriers, int numPilots);
void interp_polynomial_mag(int ind, float Hi[], float Hq[], int indH[], int len);
void interp_polynomial_iq(int ind, float Hi[], float Hq[], int indH[], int len);
int interp_polynomial_N(float Hi[], float Hq[], int pltIndx[], int numCarriers, int numPilots, int interp_order);
void interp_fft(float Hi[], float Hq[], int pltIndx[], int numCarriers, int numPilots, 
                fftwf_plan plan_fft_carrier, fftwf_plan plan_ifft_pilot);

//---------------- Auxiliary ------------------
void generate_complex_symbol(float* inI, float* inQ, float complex* outCmplx, size_t len);
void complex_multiplication(double* inI1, double* inQ1, double* inI2, double* inQ2, double* outI, double* outQ);
int save_signal(float complex* signal_cmplx, int len, char* fileName);
int clear_file(char* fileName);
int save_result_success(double BER, char* fileName);
int save_result_fail(char* fileName);
void handle_sig(int sig);
void usage(char* programName);
int save_asignal(float* t, float* signal, int len, char* fileName);
int save_1column(float* signal, int len, char* fileName);
int save_1row(float* signal, int len, char* fileName);

extern bool stop_signal;

//=========================================== Multi-Threading ===========================================

void *thread_function_0(void *thread_arg);
void *thread_function_1_1(void *thread_arg);
void *thread_function_1(void *thread_arg);
void *thread_function_2(void *thread_arg);
void *thread_function_3(void *thread_arg);

//=========================================== IIO Functions ===========================================

struct phy_cfg {
	long long bw_hz; 		// Analog banwidth in Hz
	long long fs_hz; 		// Baseband sample rate in Hz
	long long lo_hz; 		// Local oscillator frequency in Hz
	const char* rfport; 	// Port name
	const char* gain_ctrl; 	// Gain control mode
	double hw_gain;			//hardware gain
	double pwr_down;			//power down TX
};

struct Pluto_config_structure {
	struct iio_context* ctx;
	struct iio_scan_context* scan_ctx;
	struct iio_context_info** ctx_info;

	struct iio_device* rx_stream_dev; 
	struct iio_channel* rx_stream_channel_i; 
	struct iio_channel* rx_stream_channel_q; 

	struct iio_device* tx_stream_dev; 
	struct iio_channel* tx_stream_channel_i; 
	struct iio_channel* tx_stream_channel_q;

	struct phy_cfg tx_phy;
	struct phy_cfg rx_phy;
};

/* common physical channels params */
typedef struct Pluto_config_structure Pluto_config_structure;
typedef Pluto_config_structure* Pluto_cfg_ptr_t;

Pluto_cfg_ptr_t Pluto_init(bool rx_flag);

const char *getURI(Pluto_cfg_ptr_t pluto);

extern char tmpstr[64]; /* static scratch mem for strings for IIO Functions */
char* get_ch_name(const char* type, int id); /* helper function generating channel names */
void shutdown_pluto(Pluto_cfg_ptr_t pluto); /* cleanup and exit */

bool wr_ch_lli(struct iio_channel *chn, const char* what, long long val);    /* write attribute: long long int */
bool wr_ch_double(struct iio_channel *chn, const char* what, double val);	/* write attribute: double */
bool wr_ch_str(struct iio_channel *chn, const char* what, const char* str);  /* write attribute: string */

struct iio_device* get_ad9361_phy(struct iio_context *ctx);  /* returns ad9361 phy device */
bool get_rx_phy_chan(struct iio_context *ctx, int chid, struct iio_channel **chn);  /* finds AD9361 phy IIO configuration channel with id chid */
bool get_tx_phy_chan(struct iio_context *ctx, int chid, struct iio_channel **chn);

bool get_rx_lo_chan(struct iio_context *ctx, struct iio_channel **chn); /* finds AD9361 local oscillator IIO configuration channels */
bool get_tx_lo_chan(struct iio_context *ctx, struct iio_channel **chn);

bool cfg_ad9361_rx_phy_ch(Pluto_cfg_ptr_t pluto, int chid); /* configure physical channel parameters */
bool cfg_ad9361_tx_phy_ch(Pluto_cfg_ptr_t pluto, int chid);

bool get_ad9361_rx_stream_dev(struct iio_context *ctx, struct iio_device **dev);    /* finds AD9361 streaming IIO devices */
bool get_ad9361_tx_stream_dev(struct iio_context *ctx, struct iio_device **dev);

bool get_ad9361_rx_stream_ch(struct iio_device *dev, int chid, struct iio_channel **chn);   /* finds AD9361 streaming IIO channels */
bool get_ad9361_tx_stream_ch(struct iio_device *dev, int chid, struct iio_channel **chn);

//=========================================== Buffer Structure ===========================================

struct buffer_structure {
	// RX Pluto Buffer
	struct iio_buffer *pluto_tx_buffer;
	struct iio_buffer *pluto_rx_buffer;
	
	//Ring Buffer 1 
	int16_t *signal_processing_buffer_I;
	int16_t *signal_processing_buffer_Q;

	// Temporary buffer for plotting 
	double *plotting_buffer_after_I;	//after all synchronization processes
	double *plotting_buffer_after_Q;

};

//=========================================== Thread argument ===========================================

struct thread_argument_structure {
	struct buffer_structure buf;
	
	Pluto_cfg_ptr_t pluto;

	sig_pro_ptr_t sig;

	bool stop_all_threads;

};

typedef struct thread_argument_structure thread_argument_structure;
/// Handle type, the way users interact with the API
typedef struct thread_argument_structure* thread_argument_ptr_t;

thread_argument_ptr_t thread_argument_init(bool rx_flag);

void thread_argument_reset(thread_argument_ptr_t arg);
void thread_argument_free(thread_argument_ptr_t arg);


//========================================================================================================
void usage(char* programName);

//int sockfd;
//struct sockaddr_in saddr;

#endif // RECEIVER_H_INCLUDED
