#include "pluto.h"

sig_pro_ptr_t signal_processing_parameters_init(void)
{
	sig_pro_ptr_t signal_process = malloc(sizeof(struct signal_processing_structure));

    int NUM_BLOCKS_PER_SLOT = NUM_DATA_BLOCKS + NUM_SYN_BLOCKS + NUM_EST_BLOCKS + NUM_CTRL_BLOCKS;

    signal_process->slot_cnt = 0;

    signal_process->burst_len = 32;

    signal_process->symbols_per_block = NSC + CP_LEN;
    signal_process->symbols_per_slot = NUM_BLOCKS_PER_SLOT * signal_process->symbols_per_block;

    //the total number of samples in a slot
    signal_process->total_slot_len = signal_process->symbols_per_slot + signal_process->burst_len;

    signal_process->tx_I = (float*) calloc(signal_process->total_slot_len, sizeof(float));
    signal_process->tx_Q = (float*) calloc(signal_process->total_slot_len, sizeof(float)); 

    signal_process->rx_I = (float*) malloc(signal_process->total_slot_len * 2 * sizeof(float));
	signal_process->rx_Q = (float*) malloc(signal_process->total_slot_len * 2 * sizeof(float));

	// m and gold sequence initialization
    signal_process->seqLen = 127;           // the length of m and gold sequences
    signal_process->syncSigStartIndex = 55; // first subcarrier to put m and gold sequence
    signal_process->Nid_1 = 170;            // Cell ID 1
    signal_process->Nid_2 = 2;              // Cell ID 2
    signal_process->bitsPerSymbolPreamble = BPSK;
    //upsampled m and gold sequence
    signal_process->mUI = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    signal_process->mUQ = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    signal_process->goldUI = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    signal_process->goldUQ = (float*) calloc(signal_process->symbols_per_block, sizeof(float));

    // Pilots index and value generation
    signal_process->numPilots = 32;         // set number of pilot carriers 
    signal_process->bitsPerSymbolPilot = QPSK;
    
    signal_process->pilot_bits_per_block = signal_process->numPilots * signal_process->bitsPerSymbolPilot;
    
    signal_process->num_data_subcarrier = NSC - signal_process->numPilots - 3;  // number of data subcarriers

    signal_process->tx_bitsPerSymbol = QAM16;
    signal_process->tx_data_bits_per_block = signal_process->num_data_subcarrier * signal_process->tx_bitsPerSymbol;

    signal_process->rx_bitsPerSymbol = QAM16;
    signal_process->rx_data_bits_per_block = signal_process->num_data_subcarrier * signal_process->rx_bitsPerSymbol;

	//================================= READ TX DATA BITS ====================================================
	signal_process->tx_data_bits = (float*) malloc(signal_process->tx_data_bits_per_block * NUM_DATA_BLOCKS * sizeof(float));

	FILE *file_data_tx  = fopen("Data_Bits.txt", "r"); // read only

	// test for files not existing.
	if (file_data_tx == NULL) {
		printf("Error! Could not open Data file! Close the program.\n");
		return NULL;
	}

	size_t tx_data_bit_cnt = 0;
	float tx_num_data_tmp;

	while ((fscanf(file_data_tx, "%f", &tx_num_data_tmp) != EOF) && 
            (tx_data_bit_cnt < signal_process->tx_data_bits_per_block * NUM_DATA_BLOCKS)) {
		
        signal_process->tx_data_bits[tx_data_bit_cnt++] = tx_num_data_tmp;
	}


	//================================= READ RX DATA BITS ====================================================
	signal_process->rx_data_bits = (float*) malloc(signal_process->rx_data_bits_per_block * NUM_DATA_BLOCKS * sizeof(float));

	FILE *file_data_rx  = fopen("Data_Bits.txt", "r"); // read only

	// test for files not existing.
	if (file_data_rx == NULL) {
		printf("Error! Could not open Data file! Close the program.\n");
		return NULL;
	}

	size_t rx_data_bit_cnt = 0;
	float rx_num_data_tmp;

	while ((fscanf(file_data_rx, "%f", &rx_num_data_tmp) != EOF) && 
            (rx_data_bit_cnt < signal_process->rx_data_bits_per_block * NUM_DATA_BLOCKS)) {
		
        signal_process->rx_data_bits[rx_data_bit_cnt++] = rx_num_data_tmp;
	}

	//================================= READ PILOT BITS ====================================================
	signal_process->pilot_bits = (float*) malloc(signal_process->pilot_bits_per_block * NUM_DATA_BLOCKS * sizeof(float));

	FILE *file_pilot  = fopen(FILE_PILOT_BITS, "r"); // read only

	// test for files not existing.
	if (file_pilot == NULL) {
		printf("Error! Could not open Pilot file! Close the program.\n");
		return NULL;
	}

	size_t pilot_bit_cnt = 0;
	float num_pilot_tmp;

	while ((fscanf(file_pilot, "%f", &num_pilot_tmp) != EOF) && 
            (pilot_bit_cnt < signal_process->pilot_bits_per_block * NUM_DATA_BLOCKS)) {
		
        signal_process->pilot_bits[pilot_bit_cnt++] = num_pilot_tmp;
	}
    //===================================================================================================

     // data and pilot subcarriers' indexes
    signal_process->dataIndx = (int*) malloc(signal_process->num_data_subcarrier * sizeof(int));
    signal_process->pltIndx = (int*) malloc(signal_process->numPilots * sizeof(int));

    //get_data_pilot_indexes(signal_process->dataIndx, signal_process->pltIndx, NSC, signal_process->numPilots, 0);
    get_pilot_indexes_for_fft_interpolation_toan(signal_process->dataIndx, signal_process->pltIndx, NSC, signal_process->numPilots);	
	//pilot indexes for FFT interpolation

    /*
    for(int i = 0; i < signal_process->numPilots; i++) {
        printf("\n\t%d", signal_process->pltIndx[i]);
    }
    printf("\nData indexes:");
    for(int i = 0; i < signal_process->num_data_subcarrier; i++) {
        printf("\n\t%d", signal_process->dataIndx[i]);
    }
    */

    // pilot sequence
    signal_process->pltI = (float*) malloc(signal_process->numPilots * NUM_DATA_BLOCKS * sizeof(float));
    signal_process->pltQ = (float*) malloc(signal_process->numPilots * NUM_DATA_BLOCKS * sizeof(float));

    generate_symbols(signal_process->pilot_bits, signal_process->bitsPerSymbolPilot, signal_process->numPilots * NUM_DATA_BLOCKS, 
                        signal_process->pltI, signal_process->pltQ);
/*
    save_1row(signal_process->pltI, signal_process->numPilots * NUM_DATA_BLOCKS, "Pilot_Symbols_I.txt");
    save_1row(signal_process->pltQ, signal_process->numPilots * NUM_DATA_BLOCKS, "Pilot_Symbols_Q.txt");
*/
    signal_process->PSSGain = 0;


    fftwf_complex* in_temp_1 = (fftwf_complex*) fftwf_malloc(NSC * sizeof(fftwf_complex));
	fftwf_complex* out_temp_1 = (fftwf_complex*) fftwf_malloc(NSC * sizeof(fftwf_complex)); 	
	signal_process->plan_fft = fftwf_plan_dft_1d(NSC, in_temp_1, out_temp_1, FFTW_FORWARD, FFTW_PATIENT);
    fftw_free(in_temp_1);
	fftw_free(out_temp_1);

    fftwf_complex* in_temp_2 = (fftwf_complex*) fftwf_malloc(NSC * sizeof(fftwf_complex));
	fftwf_complex* out_temp_2 = (fftwf_complex*) fftwf_malloc(NSC * sizeof(fftwf_complex)); 	
	signal_process->plan_ifft = fftwf_plan_dft_1d(NSC, in_temp_2, out_temp_2, FFTW_BACKWARD, FFTW_PATIENT);
    fftw_free(in_temp_2);
	fftw_free(out_temp_2);

    fftwf_complex* in_temp_3 = (fftwf_complex*) fftwf_malloc(signal_process->numPilots * sizeof(fftwf_complex));
	fftwf_complex* out_temp_3 = (fftwf_complex*) fftwf_malloc(signal_process->numPilots * sizeof(fftwf_complex)); 	
	signal_process->plan_ifft_pilot = fftwf_plan_dft_1d(signal_process->numPilots, in_temp_3, out_temp_3, 
                                                            FFTW_BACKWARD, FFTW_PATIENT);
    fftw_free(in_temp_3);
	fftw_free(out_temp_3);

    fftwf_complex* in_temp_4 = (fftwf_complex*) fftwf_malloc(NSC * 2 * sizeof(fftwf_complex));
	fftwf_complex* out_temp_4 = (fftwf_complex*) fftwf_malloc(NSC * 2 * sizeof(fftwf_complex)); 	
	signal_process->plan_fft_corr = fftwf_plan_dft_1d(NSC * 2, in_temp_4, out_temp_4, FFTW_FORWARD, FFTW_PATIENT);
    fftw_free(in_temp_4);
	fftw_free(out_temp_4);

    fftwf_complex* in_temp_5 = (fftwf_complex*) fftwf_malloc(NSC * 2 * sizeof(fftwf_complex));
	fftwf_complex* out_temp_5 = (fftwf_complex*) fftwf_malloc(NSC * 2 * sizeof(fftwf_complex)); 	
	signal_process->plan_ifft_corr = fftwf_plan_dft_1d(NSC * 2, in_temp_5, out_temp_5, FFTW_BACKWARD, FFTW_PATIENT);
    fftw_free(in_temp_5);
	fftw_free(out_temp_5);

    strcpy(signal_process->file_channel_IQ_name, "Estimated_Channel_IQ_Response_0.txt");
    strcpy(signal_process->file_channel_Complex_name, "Complex_Channel_Response_0.txt");
    strcpy(signal_process->file_Constellation_name, "Equalized_Data_Symbols_0.txt");

	return signal_process;
}


void signal_processing_parameters_free(sig_pro_ptr_t signal_process)
{
	free(signal_process->tx_data_bits);
    free(signal_process->rx_data_bits);
	free(signal_process->pilot_bits);

    free(signal_process->dataIndx);
    free(signal_process->pltIndx);

    free(signal_process->pltI);
    free(signal_process->pltQ);

    free(signal_process->mUI);
    free(signal_process->mUQ);
    free(signal_process->goldUI);
    free(signal_process->goldUQ);

	free(signal_process->tx_I);
    free(signal_process->tx_Q);

    free(signal_process->rx_I);
    free(signal_process->rx_Q);

    fftwf_destroy_plan(signal_process->plan_ifft);
    fftwf_destroy_plan(signal_process->plan_fft);
    fftwf_destroy_plan(signal_process->plan_ifft_pilot);
    fftwf_destroy_plan(signal_process->plan_fft_corr);
    fftwf_destroy_plan(signal_process->plan_ifft_corr);

	free(signal_process);
}


void m_seq(float* preambleI, float* preambleQ, int len, int bitsPerSymbolPreamble, int Nid_2) {

    unsigned char x_init[7] = {1, 1, 1, 0, 1, 1, 0}; // initial state
    unsigned char x[len];
    int m;

    for (int i = 0; i < len; i++) { 
        if (i < 7)  x[i] = x_init[i];
        else    x[i] = (x[i - 3] + x[i - 7]) % 2; 
    }

    for (int n = 0; n < len; n++) {
        m = (n + 43 * Nid_2) % len;
        preambleI[n] = - (1 - 2 * x[m]) * sqrt(NSC/(float)len); // BPSK modulation, was rotated for 180 degrees
        //preambleI[n] = - (1 - 2 * x[m]) *3;
        preambleQ[n] = 0;
    }

}

void gold_seq(float* preambleI, float* preambleQ, int len, int bitsPerSymbolPreamble, int Nid_1, int Nid_2) {

    unsigned char x0_init[7] = {0, 0, 0, 0, 0, 0, 1};
    unsigned char x1_init[7] = {0, 0, 0, 0, 0, 0, 1};
    unsigned char x0[len];
    unsigned char x1[len];
    int m0;
    int m1;

    for (int i = 0; i < len; i++) { 
        if (i < 7)  { 
            x0[i] = x0_init[i]; 
            x1[i] = x1_init[i]; 
        }
        else {  
            x0[i] = (x0[i - 3] + x0[i - 7]) % 2;
            x1[i] = (x1[i - 6] + x1[i - 7]) % 2;
        } 
    }

    for (int n = 0; n < len; n++) {
        m0 = 15 * (int) (floor(Nid_1 / 112.0)) + 5 * Nid_2;
        m1 = Nid_1 % 112;
        preambleI[n] = (1 - 2 * x0[(n + m0) % len]) * (1 - 2 * x1[(n + m1) % len])* sqrt(NSC/(float)len); // BPSK modulated
        //preambleI[n] = (1 - 2 * x0[(n + m0) % len]) * (1 - 2 * x1[(n + m1) % len])*3;
        preambleQ[n] = 0;
    }

}

void idft(float* inI, float* inQ, int len, float* outI, float* outQ) {
    for (int i = 0; i < len; i++) {
        
        float lenD = (float) len;
        
        outI[i] = 0;
        outQ[i] = 0;
        
        for (int j = 0; j < len; j++) {
            outI[i] += inI[j] * cos(2 * PI * i * j / lenD) 
                    - inQ[j] * sin(2 * PI * i * j / lenD);
            outQ[i] += inQ[j] * cos(2 * PI * i * j / lenD) 
                    + inI[j] * sin(2 * PI * i * j / lenD);
        }
        
        outI[i] /= sqrt(lenD);
        outQ[i] /= sqrt(lenD);
    }
}

void fft_with_rearrange( float complex* inCmplx, float *outI, float *outQ, int len, fftwf_plan plan_forward ) {
    float tmp_coefficient = (float) sqrt(len);
    float complex* outCmplx = (float complex*) calloc(len, sizeof(float complex));

    fftwf_execute_dft(plan_forward, inCmplx, outCmplx);
    rearrange_spectrum(len, outCmplx);

    for (int z = 0; z < len; z++) {
            outI[z] = crealf(outCmplx[z]) / tmp_coefficient;
            outQ[z] = cimagf(outCmplx[z]) / tmp_coefficient;
    }

    free(outCmplx);
}

void fft_without_rearrange( float complex* inCmplx, float *outI, float *outQ, int len, fftwf_plan plan_forward ) {
    float tmp_coefficient = (float) sqrt(len);
    float complex* outCmplx = (float complex*) calloc(len, sizeof(float complex));

    fftwf_execute_dft(plan_forward, inCmplx, outCmplx);

    for (int z = 0; z < len; z++) {
            outI[z] = crealf(outCmplx[z]) / tmp_coefficient;
            outQ[z] = cimagf(outCmplx[z]) / tmp_coefficient;
    }

    free(outCmplx);
}

void ifft_new( float complex* inCmplx, float *outI, float *outQ, int len, fftwf_plan plan_backward ) {
    float tmp_coefficient = (float) sqrt(len);
    float complex* outCmplx = (float complex*) calloc(len, sizeof(float complex));

    fftwf_execute_dft(plan_backward, inCmplx, outCmplx);

    for (int z = 0; z < len; z++) {
            outI[z] = crealf(outCmplx[z]) / tmp_coefficient;
            outQ[z] = cimagf(outCmplx[z]) / tmp_coefficient;
    }

    free(outCmplx);
}

void rearrange_spectrum(long long len, float complex* mag){

    float complex* tmp = (float complex*) malloc((len / 2) * sizeof(float complex));
	for (int i = 0; i < len / 2; i++){
		tmp[i] = mag[i + len / 2];
		mag[i + len / 2] = mag[i];
		mag[i] = tmp[i];
	}
	free(tmp);
}

/* 
   ifft(v,N):
   [0] If N==1 then return.
   [1] For k = 0 to N/2-1, let ve[k] = v[2*k]
   [2] Compute ifft(ve, N/2);
   [3] For k = 0 to N/2-1, let vo[k] = v[2*k+1]
   [4] Compute ifft(vo, N/2);
   [5] For m = 0 to N/2-1, do [6] through [9]
   [6]   Let w.re = cos(2*PI*m/N)
   [7]   Let w.im = sin(2*PI*m/N)
   [8]   Let v[m] = ve[m] + w*vo[m]
   [9]   Let v[m+N/2] = ve[m] - w*vo[m]
 */
void ifft(cmplx *v, int len, cmplx *tmp ) {
    if(len > 1) { /* otherwise, do nothing and return */  
        cmplx z, w, *vo, *ve;
        ve = tmp; 
        vo = tmp + len / 2;
        for(int k = 0; k < len/2; k++) {
          ve[k] = v[2*k];
          vo[k] = v[2*k+1];
        }
        ifft( ve, len/2, v ); /* FFT on even-indexed elements of v[] */
        ifft( vo, len/2, v ); /* FFT on odd-indexed elements of v[] */
        for(int m = 0; m < len/2; m++) {
          w.Re = cos(2*PI*m / (float) len);
          w.Im = sin(2*PI*m / (float) len);
          z.Re = w.Re*vo[m].Re - w.Im*vo[m].Im;	/* Re(w*vo[m]) */
          z.Im = w.Re*vo[m].Im + w.Im*vo[m].Re;	/* Im(w*vo[m]) */
          v[  m  ].Re = ve[m].Re + z.Re;
          v[  m  ].Im = ve[m].Im + z.Im;
          v[m+len/2].Re = ve[m].Re - z.Re;
          v[m+len/2].Im = ve[m].Im - z.Im;
        }
    }
    return;
}

/* 
   fft(v,N):
   [0] If N==1 then return.
   [1] For k = 0 to N/2-1, let ve[k] = v[2*k]
   [2] Compute fft(ve, N/2);
   [3] For k = 0 to N/2-1, let vo[k] = v[2*k+1]
   [4] Compute fft(vo, N/2);
   [5] For m = 0 to N/2-1, do [6] through [9]
   [6]   Let w.re = cos(2*PI*m/N)
   [7]   Let w.im = -sin(2*PI*m/N)
   [8]   Let v[m] = ve[m] + w*vo[m]
   [9]   Let v[m+N/2] = ve[m] - w*vo[m]
 */
void fft( cmplx *v, int len, cmplx *tmp ) {
  if(len > 1) {	 /* otherwise, do nothing and return */
    cmplx z, w, *vo, *ve;
    ve = tmp; 
    vo = tmp + len / 2;
    for(int k = 0; k < len/2; k++) {
      ve[k] = v[2*k];
      vo[k] = v[2*k+1];
    }
    fft(ve, len/2, v); /* FFT on even-indexed elements of v[] */
    fft(vo, len/2, v); /* FFT on odd-indexed elements of v[] */
    for(int m = 0; m < len/2; m++) {
      w.Re = cos(2*PI*m / (float) len);
      w.Im = -sin(2*PI*m / (float) len);
      z.Re = w.Re*vo[m].Re - w.Im*vo[m].Im; /* Re(w*vo[m]) */
      z.Im = w.Re*vo[m].Im + w.Im*vo[m].Re; /* Im(w*vo[m]) */
      v[m].Re = ve[m].Re + z.Re;
      v[m].Im = ve[m].Im + z.Im;
      v[m+len/2].Re = ve[m].Re - z.Re;
      v[m+len/2].Im = ve[m].Im - z.Im;
    }
  }
  return;
}
