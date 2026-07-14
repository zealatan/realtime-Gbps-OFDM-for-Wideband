#include "pluto.h"


void generate_transmit_slot(sig_pro_ptr_t signal_process){    
    

    float* tx_I1 = (float*) malloc(signal_process->symbols_per_slot* sizeof(float));
    float* tx_Q1 = (float*) malloc(signal_process->symbols_per_slot* sizeof(float));
        
    // Buffer initialization for m and gold sequence
    float* mI = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    float* mQ = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    float* mModI = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    float* mModQ = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    float* goldI = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    float* goldQ = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    float* goldModI = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    float* goldModQ = (float*) calloc(signal_process->symbols_per_block, sizeof(float));

	/*
    // Buffer initialization for channel estimate and control frame
    float* estI = (float*) malloc(signal_process->symbols_per_block * sizeof(float));
    float* estQ = (float*) malloc(signal_process->symbols_per_block * sizeof(float));
    float* estModI = (float*) malloc(signal_process->symbols_per_block * sizeof(float));
    float* estModQ = (float*) malloc(signal_process->symbols_per_block * sizeof(float));
    float* ctrI = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    float* ctrQ = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    float* ctrModI = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    float* ctrModQ = (float*) calloc(signal_process->symbols_per_block, sizeof(float));

    // Buffer initialization for upsampled channel estimate and control frame
    float* estUI = (float*) malloc(signal_process->symbols_per_block * sizeof(float));
    float* estUQ = (float*) malloc(signal_process->symbols_per_block * sizeof(float));
    float* ctrUI = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    float* ctrUQ = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
	*/

	   
	float* txSymI = (float*) calloc(NSC, sizeof(float));
    float* txSymQ = (float*) calloc(NSC, sizeof(float));
    float complex* txSymCmplx = (float complex*) calloc(NSC, sizeof(float complex));

    // Tx symbols after ifft is applied to modulate subcarriers
    float* txModI = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    float* txModQ = (float*) calloc(signal_process->symbols_per_block, sizeof(float));
    float complex* txModCmplx = (float complex*) calloc(NSC, sizeof(float complex));
    float complex* freq_spectrum = (float complex*) calloc(NSC, sizeof(float complex));
    float* freq_spectrum_mag = (float*) calloc(NSC, sizeof(float));

    // Buffer initialization for data symbols
    float* dataSymI = (float*) calloc(signal_process->num_data_subcarrier, sizeof(float));
    float* dataSymQ = (float*) calloc(signal_process->num_data_subcarrier, sizeof(float)); 
    
    
    //////////////////////////////////////////////
    ////////////////// TRANSMITTER: ////////////// 
    //////////////////////////////////////////////
   
    // Generating sequences for sync (m-seq and gold-seq)
    m_seq(mI + signal_process->syncSigStartIndex + CP_LEN, mQ + signal_process->syncSigStartIndex + CP_LEN, 
            signal_process->seqLen, signal_process->bitsPerSymbolPreamble, signal_process->Nid_2);    
    for(int n = 0; n < NSC; n++){
        signal_process->mUI[n + CP_LEN] = mI[n + CP_LEN];
        signal_process->mUQ[n + CP_LEN] = mQ[n + CP_LEN];
    }
    idft(signal_process->mUI + CP_LEN, signal_process->mUQ + CP_LEN, NSC, mModI + CP_LEN, mModQ + CP_LEN);
    insert_cp(NSC, CP_LEN, mModI, mModQ);

    gold_seq(goldI + signal_process->syncSigStartIndex + CP_LEN, goldQ + signal_process->syncSigStartIndex + CP_LEN, 
                signal_process->seqLen, signal_process->bitsPerSymbolPreamble, signal_process->Nid_1, signal_process->Nid_2);
    for(int n = 0; n < NSC; n++){
        signal_process->goldUI[n + CP_LEN] = goldI[n + CP_LEN];
        signal_process->goldUQ[n + CP_LEN] = goldQ[n + CP_LEN];
    }    
    idft(signal_process->goldUI + CP_LEN, signal_process->goldUQ + CP_LEN, NSC, goldModI + CP_LEN, goldModQ + CP_LEN);
    insert_cp(NSC, CP_LEN, goldModI, goldModQ);
    
    // Store synchronization signalssequence in a slot
    for (int k = 0; k < NUM_SYN_BLOCKS; k+=2) {
        store_in_aslot(mModI, mModQ, signal_process->symbols_per_block, 
                        tx_I1 + k * signal_process->symbols_per_block, 
                        tx_Q1 + k * signal_process->symbols_per_block);
        store_in_aslot(goldModI, goldModQ, signal_process->symbols_per_block, 
                        tx_I1 + (k + 1) * signal_process->symbols_per_block, 
                        tx_Q1 + (k + 1) * signal_process->symbols_per_block);
    }


    // Add data in a slot
    for (int k = 0; k < NUM_DATA_BLOCKS; k++) {
         
		generate_symbols(signal_process->tx_data_bits + k * signal_process->tx_data_bits_per_block, 
							signal_process->tx_bitsPerSymbol, signal_process->num_data_subcarrier, dataSymI, dataSymQ);

        // insert pilot
        insert_symbols_fdm(txSymI, txSymQ, 
							signal_process->pltI + k * signal_process->numPilots, 
							signal_process->pltQ + k * signal_process->numPilots, 
							signal_process->pltIndx, signal_process->numPilots);
        // insert data into data carriers
        insert_symbols_fdm(txSymI, txSymQ, dataSymI, dataSymQ, signal_process->dataIndx, signal_process->num_data_subcarrier);
        //save_asignal(txSymI, txSymQ, symbols_per_block, "TX_Symbol.txt");

        generate_complex_symbol(txSymI, txSymQ, txSymCmplx, NSC);
        rearrange_spectrum(NSC, txSymCmplx);
        ifft_new( txSymCmplx, txModI + CP_LEN, txModQ + CP_LEN, NSC, signal_process->plan_ifft );
                       
        insert_cp(NSC, CP_LEN, txModI, txModQ);
        //save_asignal(txModI, txModQ, symbols_per_block, "OFDMDataSymbols.txt");

        store_in_aslot(txModI, txModQ, signal_process->symbols_per_block, 
			            tx_I1 + (NUM_SYN_BLOCKS + NUM_EST_BLOCKS + NUM_CTRL_BLOCKS + k) * signal_process->symbols_per_block, 
			            tx_Q1 + (NUM_SYN_BLOCKS + NUM_EST_BLOCKS + NUM_CTRL_BLOCKS + k) * signal_process->symbols_per_block);

/*
        //----------------------------------------- GENERATE PSD AND FREQUENCY SPECTRUM ---------------------------------------
        
        for(int z = 0; z < NSC; z++) {
            txModI[CP_LEN + z] *= pow(2,0);
            txModQ[CP_LEN + z] *= pow(2,0);
        }

        float frequency_resolution = (float)(1000000.0 / NSC);

        float* frequency_bin_spectrum = (float*) malloc(NSC * sizeof(float));        
        for (int z = 0; z < NSC; z++) {
            int tmp = z - (NSC / 2);
            frequency_bin_spectrum[z] = tmp * frequency_resolution;
        }
        generate_complex_symbol(txModI + CP_LEN, txModQ + CP_LEN, txModCmplx, NSC);
        fftwf_execute_dft(signal_process->plan_fft, txModCmplx, freq_spectrum);  //generate frequency spectrum
        rearrange_spectrum(NSC, freq_spectrum);
        for (int z = 0; z < NSC; z++) {
            freq_spectrum_mag[z] = cabsf(freq_spectrum[z]);
        }
        save_asignal(frequency_bin_spectrum, freq_spectrum_mag, NSC, "TX_Frequency_Spectrum.txt");

        free(frequency_bin_spectrum);
        //---------------------------------------------------------------------------------------------------------
*/        
    }

    memcpy(signal_process->tx_I + signal_process->burst_len, tx_I1, signal_process->symbols_per_slot* sizeof(float));
    memcpy(signal_process->tx_Q + signal_process->burst_len, tx_Q1, signal_process->symbols_per_slot* sizeof(float));
    //save_asignal(signal_process->tx_I, signal_process->tx_Q, signal_process->total_slot_len, "TX_Signal.txt");


	free(mI);
    free(mQ);
    free(mModI);
    free(mModQ);
    free(goldI);
    free(goldQ);
    free(goldModI);
    free(goldModQ);

    free(tx_I1);
    free(tx_Q1);
	free(txSymI);
    free(txSymQ);
    free(txSymCmplx);

    free(txModI);
    free(txModQ);
	free(dataSymI);
	free(dataSymQ);
    
    free(txModCmplx);
    free(freq_spectrum);
    free(freq_spectrum_mag);
}            

void RMS_normalize_signal(size_t len, float* inI, float* inQ){
	float totPow = 0;
	float sqrt_avgPow = 0;

	for(int j = 0; j < len; j++){
		totPow += (inI[j] * inI[j] + inQ[j] * inQ[j]);
	}

	sqrt_avgPow = sqrt((float)(totPow / (float)len));

	for(int j = 0; j < len; j++){
		inI[j] /= sqrt_avgPow;
		inQ[j] /= sqrt_avgPow;
	}

}

void insert_cp(int signalLen, int giLen, float* txI, float* txQ) {
    for (int i = 0; i < giLen; i++) {
        txI[i] = txI[i + signalLen];
        txQ[i] = txQ[i + signalLen];
    }
}
  
void generate_symbol_bpsk(float* bits, float* symbol_I, float* symbol_Q) {
    *symbol_I = (bits[0]) ? 1 : -1;
    *symbol_Q = 0;
}

void generate_symbol_qpsk(float* bits, float* symbol_I, float* symbol_Q) {
    *symbol_I = (bits[0]) ? 1 : -1;
    *symbol_I *= SCALE_QPSK;
    
    *symbol_Q = (bits[1]) ? 1 : -1;
    *symbol_Q *= SCALE_QPSK;
}

void generate_symbol_16qam(float* bits, float* symbol_I, float* symbol_Q) {
    /*
     * Course slides, Ch2, slide 29
     */
    const float map16QAM[] = {-1 * SCALE_16QAM,
                               -3 * SCALE_16QAM,
                                1 * SCALE_16QAM,
                                3 * SCALE_16QAM};

    int tmpI = 0;
    int tmpQ = 0;

    /*for (int i = 0; i < QAM16; i++) {
        printf("%hhu", bits[i]);
    }*/

    for (int i = 0; i < QAM16 / 2; i++) {
        tmpI += bits[i] * pow(2, 1 - i);
        tmpQ += bits[i + QAM16 / 2] * pow(2, 1 - i);
    }

    *symbol_I = map16QAM[tmpI];
    *symbol_Q = map16QAM[tmpQ];
}

void generate_symbol_64qam(float* bits, float* symbol_I, float* symbol_Q) {
    /* 
     * Reflect encoding for 16QAM, append to map16QAM
     * prefix first half with 0 and second half with 1 
     */
    const float map64QAM[] = {-5, -7, -3, -1, 5, 7, 3, 1};

    int tmpI = 0;
    int tmpQ = 0;

    /*for (int i = 0; i < QAM64; i++) {
        printf("%hhu", bits[i]);
    }*/

    for (int i = 0; i < QAM64 / 2; i++) {
        tmpI += bits[i] * pow(2, 2 - i);
        tmpQ += bits[i + QAM64 / 2] * pow(2, 2 - i);
    }

    *symbol_I = map64QAM[tmpI] * SCALE_64QAM;
    *symbol_Q = map64QAM[tmpQ] * SCALE_64QAM;
}

void generate_symbol_256qam(float* bits, float* symbol_I, float* symbol_Q) {
    /* 
     * Reflect encoding for 16QAM, append to map16QAM
     * prefix first half with 0 and second half with 1 
     */
    const float map256QAM[] = {-13, -15, -11, -9, -3, -1, -5, -7, 
                                 13,  15,  11,  9,  3,  1,  5,  7};

    int tmpI = 0;
    int tmpQ = 0;

    /*for (int i = 0; i < QAM256; i++) {
        printf("%hhu", bits[i]);
    }*/

    for (int i = 0; i < QAM256 / 2; i++) {
        tmpI += bits[i] * pow(2, 3 - i);
        tmpQ += bits[i + QAM256 / 2] * pow(2, 3 - i);
    }

    *symbol_I = map256QAM[tmpI] * SCALE_256QAM;
    *symbol_Q = map256QAM[tmpQ] * SCALE_256QAM;
}

int generate_asymbol(float* bits, int len, float* symbol_I, float* symbol_Q) {
    switch (len) {
        case BPSK: {
            generate_symbol_bpsk(bits, symbol_I, symbol_Q);
            break;
        }
        case QPSK: {
            generate_symbol_qpsk(bits, symbol_I, symbol_Q);
            break;
        }
        case QAM16: {
            generate_symbol_16qam(bits, symbol_I, symbol_Q);
            break;
        }
        case QAM64: {
            generate_symbol_64qam(bits, symbol_I, symbol_Q);
            break;
        }
        case QAM256: {
            generate_symbol_256qam(bits, symbol_I, symbol_Q);
            break;
        }
        default: return -1;
    }
    return 0;
}

int generate_symbols(float* txBits, int bitsPerSymbol, int howManySymbols, 
        float* txSymI, float* txSymQ){
    
    for (int i = 0; i < howManySymbols; i++) {
        generate_asymbol(txBits + i * bitsPerSymbol, bitsPerSymbol, txSymI + i, txSymQ + i);
    }
       
    return 0;
}

void store_in_aslot(float* txI, float* txQ, int signalLen, float* slotI, float* slotQ) {
    for (int i = 0; i < signalLen; i++) {
        slotI[i] = txI[i];
        slotQ[i] = txQ[i];
    }
}

//////////////////////////
//  CHANNEL ESTIMATION  //
//////////////////////////


/* Generates pilot sequence (random QPSK symbols)
 * Parameters
 *  pltI    - pilot sequence I-component samples
 *  pltQ    - pilot sequence Q-component samples
 *  len     - pilot sequence length in symbols
 */
/*
void generate_pilot_qpsk(float pltI[], float pltQ[], int len) {
    // Randomly generate QPSK symbols
    for (int i = 0; i < len; i++) {
        pltI[i] = (rand_ra() >= 0.5) ? SCALE_QPSK : -SCALE_QPSK;
        pltQ[i] = (rand_ra() >= 0.5) ? SCALE_QPSK : -SCALE_QPSK;
    }
}
*/

/* Inserts TDM pilot sequence into the frame (OFDM symbol)
 * Parameters
 *  frmI    - frame sequence (OFDM symbol) I-component
 *  frmQ    - frame sequence (OFDM symbol) Q-component
 *  pltI    - pilot sequence I-component samples
 *  pltQ    - pilot sequence Q-component samples
 *  len     - pilot sequence length in symbols
 */
/*
void insert_pilot_tdm(float frmI[], float frmQ[], float pltI[], float pltQ[], int len) {
    // copy pilot into the symbol sequence (fast copy > memory) 
    memcpy(frmI, pltI, len*sizeof(float));
    memcpy(frmQ, pltQ, len*sizeof(float));
}
*/

/* Get data and pilot subcarrier indexes.
 *
 * Parameters
 *  dataIndx    - array to be filled with indexes of data subcarries
 *  pltIndx     - array to be filled with indexes of pilot subcarries
 *  numCarriers - total number of carriers (data + pilots)
 *  numPilots   - number of pilot subcarriers
 *  lastPilot   - indicator if the last carruer should be pilot (1) or not (0)
 *  
 * >>
 * NOTE: Edge pilots are better for polynomial interpolation as there is no
 *       extrapolation error at the edges. However, the high-resolution 
 *       interpolation based on FFT fails in that case.
 * >>
 * 
 */
void get_data_pilot_indexes(int dataIndx[], int pltIndx[], int numCarriers, int numPilots, int lastPilot){
    // average pilot distance
    float pilotDist = ((float) numCarriers)/((float) numPilots);

    // if the last carrier (highest freq.) is to be a pilot
    if (lastPilot) pilotDist = ((float) numCarriers)/(numPilots-1);

    // PILOT CARRIER INDEXES
    for (int i = 0; i < numPilots; i++) {
        pltIndx[i] = (int) floor(i*pilotDist);

        /* Alternative for the case when the last carrier is not a pilot, yielding
           a smaller interpolation error at both sides. However, it results in
           frequency shift for FFT interpolation. */
        // pltIndx[i] = (int) floor(i*pilotDist) + (int) round(pilotDist/2);
    }

    // prevent overshooting index (only important for lastPilot=1)
    if (pltIndx[numPilots-1] > numCarriers-1) pltIndx[numPilots-1] = numCarriers-1;

    // DATA CARRIER INDEXES
    int k = 0, j = 0;
    for (int i = 0; i < numCarriers; i++) {
        if (i == pltIndx[k]) k++;
        else dataIndx[j++] = i;
    }
}

void get_pilot_indexes_for_fft_interpolation_toan(int dataIndx[], int pltIndx[], int numCarriers, int numPilots){
    // average pilot distance
    float pilotDist = ((float) numCarriers)/((float) numPilots);

    // PILOT CARRIER INDEXES
    for (int i = 0; i < numPilots; i++) {
        pltIndx[i] = 1 + (int) floor(i*pilotDist);
    }
    
    // DATA CARRIER INDEXES
    int k = 0, j = 0;
    for (int i = 1; i < numCarriers-1; i++) {
        if (i == pltIndx[k]) k++;
        else if (i != (numCarriers / 2)) dataIndx[j++] = i;
    }
}


/* Insert symbols onto subcarriers with given indexes.
 *
 * Parameters
 *  frmI    - frame sequence (OFDM symbol) I-component
 *  frmQ    - frame sequence (OFDM symbol) Q-component
 *  symIndx - indexes of subcarries to insert symbols
 *  symI    - symbol sequence I-component samples
 *  symQ    - symbol sequence Q-component samples
 *  symLen  - symbol sequence length
 * 
 * >>
 * NOTE: Used for both pilot and data symbols.
 * >>
 */
void insert_symbols_fdm(float frmI[], float frmQ[], float symI[], float symQ[], int symIndx[], int symLen) {
    int indx;
    for (int i = 0; i < symLen; i++) {
        // subcarrier index for i-th symbol
        indx = symIndx[i];
        // insert symbol in the frame
        frmI[indx] = symI[i];
        frmQ[indx] = symQ[i];
    }
}