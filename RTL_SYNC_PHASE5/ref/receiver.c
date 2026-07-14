#include "pluto.h"


// RECEIVER:
bool process_received_slot(sig_pro_ptr_t signal_process){ 

    bool slot_detected;
    
    size_t total_rx_frame_len = signal_process->total_slot_len * 2;

    float* rx_I1 = (float*) malloc(total_rx_frame_len * sizeof(float));
	float* rx_Q1 = (float*) malloc(total_rx_frame_len * sizeof(float));

    memcpy(rx_I1, signal_process->rx_I, total_rx_frame_len * sizeof(float));
    memcpy(rx_Q1, signal_process->rx_Q, total_rx_frame_len * sizeof(float));

    int timingOffsetEstimated = 0;

    // Symbol will be stored in NSC subcarriers after its extraction 
    float* rxSymI = (float*) calloc(NSC, sizeof(float));
    float* rxSymQ = (float*) calloc(NSC, sizeof(float));
    float* rxSym_mag = (float*) calloc(NSC, sizeof(float));

    // Data subcarriers of signal
    float* rxSymDataI = (float*) calloc(signal_process->num_data_subcarrier, sizeof(float));
    float* rxSymDataQ = (float*) calloc(signal_process->num_data_subcarrier, sizeof(float));

    float* rxEqualized_SymData_in1Slot_I = (float*) calloc(signal_process->num_data_subcarrier * NUM_DATA_BLOCKS, sizeof(float));
    float* rxEqualized_SymData_in1Slot_Q = (float*) calloc(signal_process->num_data_subcarrier * NUM_DATA_BLOCKS, sizeof(float));

    // channel transfer function estimate
    float* HestI = (float*) calloc(NSC, sizeof(float));
    float* HestQ = (float*) calloc(NSC, sizeof(float));
    float* HestI_tmp = (float*) calloc((NSC), sizeof(float));
    float* HestQ_tmp = (float*) calloc((NSC), sizeof(float));
    float complex* HestCmplx = (float complex*) malloc(NSC * sizeof(float complex));
    float* HestMag = (float*) calloc(NSC - 2, sizeof(float));
    float* HestPhase = (float*) calloc(NSC - 2, sizeof(float));
    float* eqScale = (float*) calloc(NSC, sizeof(float)); 
    
    float* rxBits = (float*) calloc(signal_process->rx_data_bits_per_block, sizeof(float));

    size_t errored_bits = 0;
    float BER = 0.0;

    // AGC 
    float smoothingFactor = 0.9; // Smoothing factor of the AGC

    float complex* rxCmplx = (float complex*) calloc(NSC, sizeof(float complex));
    float complex* freq_spectrum = (float complex*) calloc(NSC, sizeof(float complex));
    float* freq_spectrum_mag = (float*) calloc(NSC, sizeof(float));    

    

    // Synchronization
    int offset_tmp = synchronization(rx_I1, rx_Q1, total_rx_frame_len, signal_process->symbols_per_slot, 
                                        signal_process->burst_len, signal_process->mUI, signal_process->mUQ, 
                                        signal_process->goldUI, signal_process->goldUQ,
                                        signal_process->syncSigStartIndex, signal_process->seqLen, 
                                        signal_process->bitsPerSymbolPreamble, signal_process->Nid_2, 
                                        signal_process->samplingFreq, signal_process->plan_fft, 
                                        signal_process->plan_fft_corr, signal_process->plan_ifft_corr);
    
    if(offset_tmp == -1) { 
        slot_detected = false; 
        printf("Slot Detection has failed!\n"); 
        save_asignal(HestMag, HestPhase, NSC - 2, "Complex_Channel_Response_for_Beier.txt");
        save_asignal(rxEqualized_SymData_in1Slot_I, rxEqualized_SymData_in1Slot_Q, signal_process->num_data_subcarrier * NUM_DATA_BLOCKS, "Equalized_Data_Symbols_for_Beier.txt");
        goto UDP; 
    }
    else if(offset_tmp < 16) {
        timingOffsetEstimated = offset_tmp;
        printf("Estimated: %d\n", timingOffsetEstimated);
        slot_detected = true;
    }
    else { 
        timingOffsetEstimated = offset_tmp - 16;
        printf("Estimated: %d\n", timingOffsetEstimated);
        slot_detected = true;        
    }


    // AGC
    signal_process->PSSGain = agc_flex(rx_I1 + timingOffsetEstimated + 
                        signal_process->symbols_per_block * (NUM_SYN_BLOCKS + NUM_EST_BLOCKS + NUM_CTRL_BLOCKS), 
                        rx_Q1 + timingOffsetEstimated + 
                        signal_process->symbols_per_block * (NUM_SYN_BLOCKS + NUM_EST_BLOCKS + NUM_CTRL_BLOCKS), 
                        signal_process->symbols_per_block * NUM_DATA_BLOCKS, 
                        signal_process->symbols_per_block, signal_process->slot_cnt, 
                        signal_process->PSSGain, smoothingFactor);
   
    // FFT of the received data
    for (int z = 0; z < NUM_DATA_BLOCKS; z++) {

/*
        //----------------------------------------- GENERATE PSD AND FREQUENCY SPECTRUM ---------------------------------------
        float frequency_resolution = (float)(1000000.0 / NSC);

        float* frequency_bin_spectrum = (float*) malloc(NSC * sizeof(float));        
        for (int z = 0; z < NSC; z++) {
            int tmp = z - (NSC / 2);
            frequency_bin_spectrum[z] = tmp * frequency_resolution;
        }
        generate_complex_symbol(rx_I1 + CP_LEN + timingOffsetEstimated + 
                                signal_process->symbols_per_block * (NUM_SYN_BLOCKS + NUM_EST_BLOCKS + NUM_CTRL_BLOCKS + z), 
                                rx_Q1 + CP_LEN + timingOffsetEstimated + 
                                signal_process->symbols_per_block * (NUM_SYN_BLOCKS + NUM_EST_BLOCKS + NUM_CTRL_BLOCKS + z), 
                                rxCmplx, NSC);
        fftwf_execute_dft(signal_process->plan_fft, rxCmplx, freq_spectrum);  //generate frequency spectrum
        rearrange_spectrum(NSC, freq_spectrum);
        for (int z = 0; z < NSC; z++) {
            freq_spectrum_mag[z] = cabsf(freq_spectrum[z]);
        }
        for (int z = 0; z < NSC; z++) {
            freq_spectrum_mag[z] /= (float) sqrt(NSC);
        }
        save_asignal(frequency_bin_spectrum, freq_spectrum_mag, NSC, "RX_Frequency_Spectrum.txt");

        free(frequency_bin_spectrum);

        //---------------------------------------------------------------------------------------------------------
*/
        generate_complex_symbol(rx_I1 + CP_LEN + timingOffsetEstimated + 
                                signal_process->symbols_per_block * (NUM_SYN_BLOCKS + NUM_EST_BLOCKS + NUM_CTRL_BLOCKS + z), 
                                rx_Q1 + CP_LEN + timingOffsetEstimated + 
                                signal_process->symbols_per_block * (NUM_SYN_BLOCKS + NUM_EST_BLOCKS + NUM_CTRL_BLOCKS + z), 
                                rxCmplx, NSC);

        fft_with_rearrange( rxCmplx, rxSymI, rxSymQ, NSC, signal_process->plan_fft );

        // Channel Estimation based on Pilots
        ch_estimation_fdm(HestI_tmp, HestQ_tmp, rxSymI, rxSymQ, 
                            signal_process->pltI + z * signal_process->numPilots, 
                            signal_process->pltQ + z * signal_process->numPilots, 
                            signal_process->pltIndx, signal_process->numPilots); 
        // Channel Transfer Function (CTF) estimate

        // interpolate
        interp_fft(HestI_tmp, HestQ_tmp, signal_process->pltIndx, NSC, signal_process->numPilots, 
                    signal_process->plan_fft, signal_process->plan_ifft_pilot);

        if(z == (NUM_DATA_BLOCKS - 1)) {
            //save_asignal(HestI_tmp, HestQ_tmp, NSC - 2, "Estimated_Channel_IQ_Response_for_Beier.txt");
            generate_complex_symbol(HestI_tmp, HestQ_tmp, HestCmplx, NSC - 2);
            for(int k = 0; k < NSC - 2; k++) {
                HestMag[k] = 10 * log10(cabsf(HestCmplx[k]));
                HestPhase[k] = cargf(HestCmplx[k]);
            }
            save_asignal(HestMag, HestPhase, NSC - 2, "Complex_Channel_Response_for_Beier.txt");          
        }

        memcpy(HestI + 1, HestI_tmp, (NSC - 2) * sizeof(float));
        memcpy(HestQ + 1, HestQ_tmp, (NSC - 2) * sizeof(float));


        // Equalization (takes channel transfer function as input)
        fde(ZF, HestI, HestQ, rxSymI, rxSymQ, NSC, eqScale);
        //save_asignal(rxSymDI, rxSymDQ, NSC, "EqualizedSignal.txt");

        // Demodulate (detect symbols and output data bits)
        for (int k = 0; k < signal_process->num_data_subcarrier; k++){
                    rxSymDataI[k] = rxSymI[signal_process->dataIndx[k]];
                    rxSymDataQ[k] = rxSymQ[signal_process->dataIndx[k]];
        }
        memcpy(rxEqualized_SymData_in1Slot_I + z * signal_process->num_data_subcarrier, rxSymDataI, 
                    signal_process->num_data_subcarrier * sizeof(float));
        memcpy(rxEqualized_SymData_in1Slot_Q + z * signal_process->num_data_subcarrier, rxSymDataQ, 
                    signal_process->num_data_subcarrier * sizeof(float));

        decode_symbols(rxSymDataI, rxSymDataQ, signal_process->num_data_subcarrier, signal_process->rx_bitsPerSymbol, rxBits);

        for (int k = 0; k < signal_process->rx_data_bits_per_block; k++) {
		    if (rxBits[k] != signal_process->rx_data_bits[k + z * signal_process->rx_data_bits_per_block]) errored_bits++;
        }    

    }    

    signal_process->slot_cnt++;

    BER = 100.0*(float)(errored_bits)/(float)(signal_process->rx_data_bits_per_block * NUM_DATA_BLOCKS);
	printf("\n\tBER = %ld/%ld = %.2f%%\n", errored_bits, signal_process->rx_data_bits_per_block * NUM_DATA_BLOCKS, BER);

    save_asignal(rxEqualized_SymData_in1Slot_I, rxEqualized_SymData_in1Slot_Q, signal_process->num_data_subcarrier * NUM_DATA_BLOCKS, "Equalized_Data_Symbols_for_Beier.txt");

    //printf("\n\tProcessing received slot has finished!\n");
    /*
    int save_to_files_interval = 10;
    if((signal_process->slot_cnt % save_to_files_interval) == 0) {
        
        Ethernet_Client_Start();

        SendArray_TCP_API(HestMag, NSC - 1);
        SendArray_TCP_API(rxEqualized_SymData_in1Slot_I, 100);  //SendArray_TCP_API(rxEqualized_SymData_in1Slot_I, NSC - 1);
        SendArray_TCP_API(rxEqualized_SymData_in1Slot_Q, 100);  //SendArray_TCP_API(rxEqualized_SymData_in1Slot_Q, NSC - 1);

        Ethernet_Client_Close();

    }
    */

    UDP:    ; //this is an empty statement for the label UDP
    //------------------------ UDP transmission ------------------------------------
    int save_to_files_interval = 10;
    if((signal_process->slot_cnt % save_to_files_interval) == 0) {
        float combine[768];

        memcpy(combine + 1, HestMag, (NSC - 2) * sizeof(float));
        combine[0] = combine[1];
        combine[255] = combine[254];
        memcpy(combine + 256, rxEqualized_SymData_in1Slot_I, NSC * sizeof(float));
        memcpy(combine + 512, rxEqualized_SymData_in1Slot_Q, NSC * sizeof(float)); 

        /*
        char buff[3072];
        char *ptr = NULL;
        for(j=0;j<256*3;j++){
            ptr=&(combine[j]); 
            for(i=0;i<4;i++){
                buff[j*4+3-i] = *(ptr+i);
            }
        }
        sendto(sockfd,buff,3072,0,(struct ckaddr*)&saddr,sizeof(saddr));
        */

        sendto(sockfd,combine,3072,0,(struct ckaddr*)&saddr,sizeof(saddr));
    }  
    //---------------------------------------------------------------------------

    FREE:

    free(rx_I1);
    free(rx_Q1);

    free(rxSymI);
    free(rxSymQ);
    free(rxSym_mag);
    free(rxSymDataI);
    free(rxSymDataQ);
    free(rxEqualized_SymData_in1Slot_I);
    free(rxEqualized_SymData_in1Slot_Q);

    free(HestI);
    free(HestQ);
    free(HestI_tmp);
    free(HestQ_tmp);
    free(HestCmplx);
    free(HestMag);
    free(HestPhase);
    free(eqScale);
    free(rxBits);

    free(rxCmplx);
    free(freq_spectrum);
    free(freq_spectrum_mag);

    return slot_detected;

}


int synchronization( float* rxI, float* rxQ, int rxLen, int symbols_per_slot, int burst_len, 
                        float* mUI, float* mUQ, float* goldUI, float* goldUQ, 
                        int syncSigStartIndex, int seqLen, int bitsPerSymbolPreamble, int Nid_2, long long samplingFreq, 
                        fftwf_plan plan_fft, fftwf_plan plan_fft_corr, fftwf_plan plan_ifft_corr ){

    // Step 1 - Frame Detection (Energy Detector)
    float threshold = 40000;       //do more experiments to figure out the proper threshold value
    int wndLen = 25;
    int frameStart = 0;

    int idx_tmp = frame_detector(rxI, rxQ, rxLen, wndLen, threshold);
    
    if(idx_tmp == -1) { return idx_tmp; }
    else { 
        frameStart = idx_tmp; 
        //printf("Estimated Energy Detector: %d\n",frameStart);
    }
        
        
    // Step 2 - timing estimation

    // Auto-correlation arrays
    float autoCorrOutI[NSC];
    float autoCorrOutQ[NSC];

    int peakIndexAuto = VanDeBeekAutoCorrelation(rxI, rxQ, frameStart, autoCorrOutI, autoCorrOutQ);
    int slotStartIndex = 0;

    if(peakIndexAuto > burst_len) { return -1; }
    else {
        slotStartIndex = peakIndexAuto + frameStart;
        //printf("\nEstimated Timing Offset: %d\n",slotStartIndex);
    }

    // Step 3 - fractional frequency estimation and correction
    float fracfreqOffset = -atan2(( autoCorrOutQ[peakIndexAuto] ), ( autoCorrOutI[peakIndexAuto] )) / (2 * PI); 
    printf("Fractional Freq Offset: %f\n", fracfreqOffset);
    apply_carrier_freq_offset(-fracfreqOffset*samplingFreq / NSC, 0, samplingFreq, 0, symbols_per_slot, 
                                rxI + slotStartIndex, rxQ + slotStartIndex);
    
    

    // Step 4 - MEYR Algorithm on cross-correlation
    int carrierFreqOffsetInt = carrierFreqOffsetEstMeyr (rxI , rxQ, mUI, mUQ, goldUI, goldUQ, slotStartIndex, plan_fft, 
                                                           plan_fft_corr, plan_ifft_corr );
    printf("Carrier Freq Integer PSS: %d\n", carrierFreqOffsetInt);
    apply_carrier_freq_offset(-carrierFreqOffsetInt* samplingFreq / NSC , 0, samplingFreq, 0, symbols_per_slot, 
                                rxI + slotStartIndex, rxQ + slotStartIndex);
    
    // CROSS-CORRELATION in time domain for Cell ID detection of m-sequence
    // int maxIndexPSS = cellIDMseq(rxI, rxQ, syncSigStartIndex, seqLen, bitsPerSymbolPreamble, slotStartIndex, samplesPerSymbol);
    // printf("PSS Cell ID: %d\n", maxIndexPSS);

    // CROSS-CORRELATION in time domain for Cell ID detection of gold-sequence
    // int maxIndexSSS = cellIDGoldseq(rxI, rxQ, syncSigStartIndex, seqLen, bitsPerSymbolPreamble, slotStartIndex, samplesPerSymbol, Nid_2);
    // printf("SSS Cell ID: %d\n", maxIndexSSS);
    
    return slotStartIndex;
}


// Frame Detector - the first block at the receiver - Toan's version (only check the first half of the received frame)
/*
Calculate the average energy of 25 consecutive samples to check if that average energy is higher than the threshold. 
If yes, then move to the next sample and do everything again, if the condition is met 10 times then we found the start of the slot.
*/
int frame_detector(float* freqOffsetDataI, float* freqOffsetDataQ, int len, int wndLen, float threshold){

    int indexFrame = -1;
    int counterFrame = 0;
    float envelopeBlock[len / 2 + 10];
    
    // This should be commented adequately
    for (int j = 0; j < (len / 2 + 10); j++) {
        envelopeBlock[j] = 0;
        for (int i = j; i < j + wndLen; i++) {
            envelopeBlock[j] += freqOffsetDataI[i] * freqOffsetDataI[i] + freqOffsetDataQ[i] * freqOffsetDataQ[i];
        }
        envelopeBlock[j] /= (float) wndLen;
    }

    if(envelopeBlock[0] < threshold){
        //printf("\n\tCase 1\n");
        for (int j = 1; j < (len / 2 + 10); j++) {
            if (envelopeBlock[j] > threshold) {
                counterFrame += 1;
                if (counterFrame == 10) {
                    indexFrame = j + 1 - 10; 
                    break;
                }
            }
            else counterFrame = 0;
        }
    }
    else {
        //printf("\n\tCase 2");
        int startIndex = 0;
        for(int j = 1; j < (len / 2 + 10); j++) {
            if (envelopeBlock[j] < threshold) {
                startIndex = j;
                break;
            }
        }
        //printf("\n\tstartIndex = %d\n", startIndex);

        if(startIndex > 0){
            for(int j = startIndex; j < (len / 2 + 10); j++) {
                if (envelopeBlock[j] > threshold) {
                    counterFrame += 1;
                    if (counterFrame == 10) {
                        indexFrame = j + 1 - 10; 
                        break;
                    }
                }
                else counterFrame = 0;
            }
        }
    }

    //save_signal(envelopeBlock, len / 2 + 10, "EnvelopeEnergyDetector.txt");
    return indexFrame;
}

/*
// Frame Detector - the first block at the receiver - Sadaf's version
int frame_detector(float* freqOffsetDataI, float* freqOffsetDataQ, int len, int wndLen, float threshold){

    int indexFrame = -1;
    int counterFrame = 0;
    float envelopeBlock[len - wndLen];
    
    // This should be commented adequately
    for (int j = 0; j < len - wndLen; j++) {
        envelopeBlock[j] = 0;
        for (int i = j; i < j + wndLen; i++) {
            envelopeBlock[j] += freqOffsetDataI[i] * freqOffsetDataI[i] + freqOffsetDataQ[i] * freqOffsetDataQ[i];
        }
        envelopeBlock[j] /= (float) wndLen;
    }

    if(envelopeBlock[0] < threshold){
        printf("\n\tCase 1\n");
        for (int j = 1; j < len - wndLen; j++) {
            if (envelopeBlock[j] > threshold) {
                counterFrame += 1;
                if (counterFrame == 10) {
                    indexFrame = j + 1 - 10; 
                    break;
                }
            }
            else counterFrame = 0;
        } 
    }
    else if(envelopeBlock[0] >= threshold){
        printf("\n\tCase 2");
        int startIndex = 0;
        for(int j = 1; j < len - wndLen; j++) {
            if (envelopeBlock[j] < threshold) {
                startIndex = j;
                break;
            }
        }
        printf("\n\tstartIndex = %d\n", startIndex);
        for(int j = startIndex; j < len - wndLen; j++) {
            if (envelopeBlock[j] > threshold) {
                counterFrame += 1;
                if (counterFrame == 10) {
                    indexFrame = j + 1 - 10; 
                    break;
                }
            }
            else counterFrame = 0;
        }
    }
    else
        counterFrame = 0;
    //save_signal(envelopeBlock, len - wndLen, "EnvelopeEnergyDetector.txt");
    return indexFrame;
}
*/

// REFERENCE: PySDR: A Guide to SDR and DSP using Python — PySDR: A Guide to SDR and DSP using Python 0.1 documentation, chapter 14 synchronization
void apply_carrier_freq_offset(float freq_offset, float phase, int freq_sampling, int startPoint, int lenIN, float* outFadedI, float* outFadedQ) {
    float freqShiftI[lenIN];
    float freqShiftQ[lenIN];
    float tmp;

    for (int j = 0; j < lenIN; j++) {
        tmp = outFadedI[j];
        freqShiftI[j] = cos(2 * PI * freq_offset * (j + startPoint) * 1.0 / freq_sampling + phase);
        freqShiftQ[j] = sin(2 * PI * freq_offset * (j + startPoint) * 1.0 / freq_sampling + phase);
        outFadedI[j] = freqShiftI[j] * outFadedI[j] - outFadedQ[j] * freqShiftQ[j];
        outFadedQ[j] = freqShiftI[j] * outFadedQ[j] + tmp * freqShiftQ[j];
    } 
}


void fft_correlation_Meyr( float * inI1, float* inQ1, float * inI2, float* inQ2, float* outI, float* outQ, 
                        fftwf_plan plan_forward, fftwf_plan plan_backward ) {
    
    float complex* inCmplx1 = (float complex*) calloc(NSC * 2, sizeof(float complex));
    float complex* inCmplx2 = (float complex*) calloc(NSC * 2, sizeof(float complex));
    float complex* inFreq1 = (float complex*) calloc(NSC * 2, sizeof(float complex));
    float complex* inFreq2 = (float complex*) calloc(NSC * 2, sizeof(float complex));
    float complex* outCmplx = (float complex*) calloc(NSC * 2, sizeof(float complex));
    float complex* outFreq = (float complex*) calloc(NSC * 2, sizeof(float complex)); 

    generate_complex_symbol(inI1, inQ1, inCmplx1, NSC);
    generate_complex_symbol(inI2, inQ2, inCmplx2, NSC);

    fftwf_execute_dft(plan_forward, inCmplx1, inFreq1);
    fftwf_execute_dft(plan_forward, inCmplx2, inFreq2);

    for (int i = 0; i < NSC * 2; i++) {
        outFreq[i] = conjf(inFreq1[i]) * inFreq2[i];
    }

    fftwf_execute_dft(plan_backward, outFreq, outCmplx);

    for (int i = 0; i < NSC - 1; i++) {
        outI[i] = crealf(outCmplx[i + NSC + 1]) / (NSC * 2);
        outQ[i] = cimagf(outCmplx[i + NSC + 1]) / (NSC * 2);
    }

    for (int i = NSC - 1; i < NSC * 2 - 1; i++) {
        outI[i] = crealf(outCmplx[i - NSC + 1]) / (NSC * 2);
        outQ[i] = cimagf(outCmplx[i - NSC + 1]) / (NSC * 2);
    }

    free(inCmplx1);
    free(inCmplx2);
    free(inFreq1);
    free(inFreq2);
    free(outCmplx);
    free(outFreq);
}

int carrierFreqOffsetEstMeyr(float* rxI ,float* rxQ, float* mUI, float* mUQ, float* goldUI, float* goldUQ, int slotStartIndex, 
                                fftwf_plan plan_fft, fftwf_plan plan_fft_corr, fftwf_plan plan_ifft_corr){  
    float crossCorrTerm1I[NSC];
    float crossCorrTerm1Q[NSC];
    float crossCorrTerm2I[NSC];
    float crossCorrTerm2Q[NSC];
    int    crossCorrLen = 2 * NSC - 1;
    float crossCorrOut2I[crossCorrLen]; 
    float crossCorrOut2Q[crossCorrLen]; 
    float peakValue;
    float signalPSSfftI[NSC]; 
    float signalPSSfftQ[NSC];
    float signalSSSfftI[NSC]; 
    float signalSSSfftQ[NSC]; 

    float complex* rxCmplx_PSS = (float complex*) calloc(NSC, sizeof(float complex));
    float complex* rxCmplx_SSS = (float complex*) calloc(NSC, sizeof(float complex));

    generate_complex_symbol(rxI + slotStartIndex + CP_LEN, rxQ + slotStartIndex + CP_LEN, rxCmplx_PSS, NSC);
    fft_without_rearrange( rxCmplx_PSS, signalPSSfftI, signalPSSfftQ, NSC, plan_fft );

    generate_complex_symbol(rxI + slotStartIndex + 2 * CP_LEN + NSC, rxQ + slotStartIndex + 2 * CP_LEN + NSC, rxCmplx_SSS, NSC);
    fft_without_rearrange( rxCmplx_SSS, signalSSSfftI, signalSSSfftQ, NSC, plan_fft );

    // Meyr Method
    for (int j = 0; j < NSC; j++){
        crossCorrTerm1I[j] = signalPSSfftI[j] * signalSSSfftI[j] + signalPSSfftQ[j] * signalSSSfftQ[j];
        crossCorrTerm1Q[j] = -signalPSSfftI[j] * signalSSSfftQ[j] + signalPSSfftQ[j] * signalSSSfftI[j];

        crossCorrTerm2I[j] = mUI[j + CP_LEN] * goldUI[j + CP_LEN] + mUQ[j + CP_LEN] * goldUQ[j + CP_LEN];
        crossCorrTerm2Q[j] = -mUI[j + CP_LEN] * goldUQ[j + CP_LEN] + mUQ[j + CP_LEN] * goldUI[j + CP_LEN];
    }
    
    fft_correlation_Meyr( crossCorrTerm2I, crossCorrTerm2Q, crossCorrTerm1I, crossCorrTerm1Q, crossCorrOut2I, crossCorrOut2Q, 
                        plan_fft_corr, plan_ifft_corr );

    int peakIndexMeyr = find_peak_index(crossCorrOut2I, crossCorrOut2Q, crossCorrLen, &peakValue);
    int carrierFreqOffsetInt =  (peakIndexMeyr) - (NSC - 1);

    free(rxCmplx_PSS);
    free(rxCmplx_SSS);

    return carrierFreqOffsetInt;
}

int find_peak_index(float* preambleConvI, float* preambleConvQ, int preambleConvLen, float* peakValue) {
    // Find the cross-correlation peak index
    int convIndex = 0;
    *peakValue = pow(preambleConvI[0], 2) + pow(preambleConvQ[0], 2); 
    for (int f = 1; f < preambleConvLen; f++) {
        if ( pow(preambleConvI[f], 2) + pow(preambleConvQ[f], 2) > (*peakValue) ) {
            *peakValue = pow(preambleConvI[f], 2) + pow(preambleConvQ[f], 2);
            convIndex = f; 
        }
    }
    return convIndex;
}

int VanDeBeekAutoCorrelation(float* rxI, float* rxQ, int frameStart, float* autoCorrOutI, float* autoCorrOutQ ){

    float normalizedValue_1[NSC];
    float normalizedValue_2[NSC];

    auto_corr(rxI + frameStart, rxQ + frameStart, autoCorrOutI, autoCorrOutQ, NSC, CP_LEN, normalizedValue_1);
    
    for (int j = 0; j < NSC; j++){
        normalizedValue_2[j] = 2 * sqrt( pow(autoCorrOutI[j],2) + pow(autoCorrOutQ[j],2) ) - normalizedValue_1[j];
    }    
    int peakIndexAuto = find_max_index(normalizedValue_2, NSC);

    return peakIndexAuto;
}

void auto_corr(float* inI, float* inQ, float* outI, float* outQ, int nFFT, int cpLen, float* normalizedValue) {
    
    for (int m = 0; m < nFFT; m++) {
        outI[m] = 0;
        outQ[m] = 0;
        normalizedValue[m] = 0;
        for (int i = 0; i < cpLen; i++) {
            outI[m] += inI[i + m] * inI[i + m + nFFT] + inQ[i + m] * inQ[i + m + nFFT];
            outQ[m] += -inI[i + m] * inQ[i + m + nFFT] + inQ[i + m] * inI[i + m + nFFT];
            normalizedValue[m] += pow(inI[i + m + nFFT], 2) + pow(inQ[i + m + nFFT], 2) + pow(inI[i + m], 2) + pow(inQ[i + m], 2);
        }
    }
}

int find_max_index(float* maxValuBuffSSS, int len) {
    float temp = maxValuBuffSSS[0];
    int index = 0;
    for (int j = 1; j < len; j++){
        if(maxValuBuffSSS[j] > temp){
            temp = maxValuBuffSSS[j];
            index = j;
        }
    }
    return index;
}

// REFERENCE : https://liquidsdr.org/doc/agc/
float agc_flex(float* recDI, float* recDQ, int rxDLen, int blockLen, int slotIndex, 
        float previousGain, float alpha) {    
    float power = 0;
    float currentGain = 0;
    float estimatedGain = 0;

    // Calculating current gain of the preamble
    for (int i = 0; i < blockLen; i++) {
        power += (pow(recDI[i], 2) + pow(recDQ[i], 2));
    }
    currentGain = 1 / (float)(sqrt(power / (float) blockLen));
    //printf("Av power: %f\n", (power / (float) blockLen));

    // Estimated gain
    if (slotIndex == 0) estimatedGain = currentGain;
    else estimatedGain = alpha * currentGain + (1 - alpha) * previousGain;

    // Normalizing the level of the input signal
    for(int i = 0; i < rxDLen; i++) {
        recDI[i] *= estimatedGain;
        recDQ[i] *= estimatedGain;
    }
    //printf("Amplitude (AGC func): %f\n", (1 / (float) estimatedGain));
    return estimatedGain;
}

/////////////////////
//  EQUALIZATION  //
////////////////////

/* Frequency Domain Equalization (FDE)
 * Parameters
 *  equalizer - Equalizer type (i.e. ZF, MRC, MMSE)
 *  snr       - Signal-to-Noise Ratio
 *  Hi        - I-component of the channel transfer function (CFT)
 *  Hq        - Q-component of the CFT
 *  len       - length of the CFT / symbol frame (number of OFDM subcarriers)
 *  RXSigI    - I-component of the signal over the symbol frame
 *  RXSigQ    - Q-component of the signal over the symbol frame
 */
int fde(equalizerType equalizer, float* Hi, float* Hq,
        float* RXSigI, float* RXSigQ, int len, float* eqScale) {

    //float eqScale;
    float tmp;

    for (int i = 0; i < len; i++) {
        // Multiply signal with channel transfer function conjugate
        tmp = RXSigI[i];
        RXSigI[i] = RXSigI[i] * Hi[i] + RXSigQ[i] * Hq[i];
        RXSigQ[i] = RXSigQ[i] * Hi[i] - tmp * Hq[i];

        // Apply appropriate scaling factor, depending on the equalization method
        switch (equalizer) {
            case ZF: { eqScale[i] = (Hi[i] * Hi[i] + Hq[i] * Hq[i]);  break; }
            case MRC: { eqScale[i] = 1; break; }
            //case MMSE: { eqScale[i] = (Hi[i] * Hi[i] + Hq[i] * Hq[i]) + 1.0 / snr; break; }
            default: { printf("Unknown Equalizer!!!\n"); return EXIT_FAILURE; }
        }
        
        RXSigI[i] /= eqScale[i];
        RXSigQ[i] /= eqScale[i];
    }
    return EXIT_SUCCESS;
}

void decode_bpsk(float* recSymI, float* recSymQ, 
        float* recBit) {    
    
    /*
     * Does not really matter since compared to 0, 
     * but keeps everything consistent 
     */
    //*recSymI /= (sqrtSNR * SQRT_OF_2);
    //*recSymQ /= (sqrtSNR * SQRT_OF_2);
    *recBit = (*recSymI > 0) ? 1 : 0;
}

void decode_qpsk(float* recSymI, float* recSymQ, 
        float* recBits) {
    
    /*
     * Does not really matter since compared to 0, 
     * but keeps everything consistent 
     */
    //*recSymI /= (sqrtSNR * SQRT_OF_2);
    //*recSymQ /= (sqrtSNR * SQRT_OF_2);
    
    recBits[0] = (*recSymI > 0) ? 1 : 0;
    recBits[1] = (*recSymQ > 0) ? 1 : 0;
}

void decode_16qam(float* recSymI, float* recSymQ, float* recBits) {
    
    const float demap16QAM[] = {-2 * SCALE_16QAM,
                                  0,
                                  2 * SCALE_16QAM};
    
    /*
     * Noise has power 2\sigma^2, so the signal is scaled with sqrt(2)
     * We revert it here
     */                                  
    //*recSymI /= (sqrtSNR * SQRT_OF_2);
    //*recSymQ /= (sqrtSNR * SQRT_OF_2);
    
    if (*recSymI < demap16QAM[0]) {
        recBits[0] = 0;
        recBits[1] = 1;
    } else if ((*recSymI >= demap16QAM[0]) && (*recSymI < demap16QAM[1])) {
        recBits[0] = 0;
        recBits[1] = 0;
    } else if ((*recSymI >= demap16QAM[1]) && (*recSymI < demap16QAM[2])) {
        recBits[0] = 1;
        recBits[1] = 0;
    } else if ((*recSymI >= demap16QAM[2])) {
        recBits[0] = 1;
        recBits[1] = 1;
    }

    if (*recSymQ < demap16QAM[0]) {
        recBits[2] = 0;
        recBits[3] = 1;
    } else if ((*recSymQ >= demap16QAM[0]) && (*recSymQ < demap16QAM[1])) {
        recBits[2] = 0;
        recBits[3] = 0;
    } else if ((*recSymQ >= demap16QAM[1]) && (*recSymQ < demap16QAM[2])) {
        recBits[2] = 1;
        recBits[3] = 0;
    } else if ((*recSymQ >= demap16QAM[2])) {
        recBits[2] = 1;
        recBits[3] = 1;
    }

}

void decode_64qam(float* recSymI, float* recSymQ, float* recBits) {
    
    const float demap16QAM[] = {-6 * SCALE_64QAM,
                                 -4 * SCALE_64QAM,
                                 -2 * SCALE_64QAM,
                                  0,
                                  2 * SCALE_64QAM,
                                  4 * SCALE_64QAM, 
                                  6 * SCALE_64QAM};
    
    /*
     * Noise has power 2\sigma^2, so the signal is scaled with sqrt(2)
     * We revert it here
     */ 
    //*recSymI /= (sqrtSNR * SQRT_OF_2);
    //*recSymQ /= (sqrtSNR * SQRT_OF_2);

    if (*recSymI < demap16QAM[0]) {
        recBits[0] = 0;
        recBits[1] = 0;
        recBits[2] = 1;
    } else if ((*recSymI >= demap16QAM[0]) && (*recSymI < demap16QAM[1])) {
        recBits[0] = 0;
        recBits[1] = 0;
        recBits[2] = 0;
    } else if ((*recSymI >= demap16QAM[1]) && (*recSymI < demap16QAM[2])) {
        recBits[0] = 0;
        recBits[1] = 1;
        recBits[2] = 0;
    } else if ((*recSymI >= demap16QAM[2]) && (*recSymI < demap16QAM[3])) {
        recBits[0] = 0;
        recBits[1] = 1;
        recBits[2] = 1;
    } else if ((*recSymI >= demap16QAM[3]) && (*recSymI < demap16QAM[4])) {
        recBits[0] = 1;
        recBits[1] = 1;
        recBits[2] = 1;
    } else if ((*recSymI >= demap16QAM[4]) && (*recSymI < demap16QAM[5])) {
        recBits[0] = 1;
        recBits[1] = 1;
        recBits[2] = 0;
    } else if ((*recSymI >= demap16QAM[5]) && (*recSymI < demap16QAM[6])) {
        recBits[0] = 1;
        recBits[1] = 0;
        recBits[2] = 0;
    } else if ((*recSymI >= demap16QAM[6])) {
        recBits[0] = 1;
        recBits[1] = 0;
        recBits[2] = 1;
    }

    if (*recSymQ < demap16QAM[0]) {
        recBits[3] = 0;
        recBits[4] = 0;
        recBits[5] = 1;
    } else if ((*recSymQ >= demap16QAM[0]) && (*recSymQ < demap16QAM[1])) {
        recBits[3] = 0;
        recBits[4] = 0;
        recBits[5] = 0;
    } else if ((*recSymQ >= demap16QAM[1]) && (*recSymQ < demap16QAM[2])) {
        recBits[3] = 0;
        recBits[4] = 1;
        recBits[5] = 0;
    } else if ((*recSymQ >= demap16QAM[2]) && (*recSymQ < demap16QAM[3])) {
        recBits[3] = 0;
        recBits[4] = 1;
        recBits[5] = 1;
    } else if ((*recSymQ >= demap16QAM[3]) && (*recSymQ < demap16QAM[4])) {
        recBits[3] = 1;
        recBits[4] = 1;
        recBits[5] = 1;
    } else if ((*recSymQ >= demap16QAM[4]) && (*recSymQ < demap16QAM[5])) {
        recBits[3] = 1;
        recBits[4] = 1;
        recBits[5] = 0;
    } else if ((*recSymQ >= demap16QAM[5]) && (*recSymQ < demap16QAM[6])) {
        recBits[3] = 1;
        recBits[4] = 0;
        recBits[5] = 0;
    } else if ((*recSymQ >= demap16QAM[6])) {
        recBits[3] = 1;
        recBits[4] = 0;
        recBits[5] = 1;
    }

}

void decode_256qam(float* recSymI, float* recSymQ, float* recBits) {
    
    const float demap256QAM[] = {-14 * SCALE_256QAM,
                                  -12 * SCALE_256QAM,    
                                  -10 * SCALE_256QAM,
                                   -8 * SCALE_256QAM,
                                   -6 * SCALE_256QAM,
                                   -4 * SCALE_256QAM,
                                   -2 * SCALE_256QAM,
                                    0,
                                    2 * SCALE_256QAM,
                                    4 * SCALE_256QAM, 
                                    6 * SCALE_256QAM,
                                    8 * SCALE_256QAM,
                                   10 * SCALE_256QAM,
                                   12 * SCALE_256QAM,
                                   14 * SCALE_256QAM};
    
    /*
     * Noise has power 2\sigma^2, so the signal is scaled with sqrt(2)
     * We revert it here
     */ 
    //*recSymI /= (sqrtSNR * SQRT_OF_2);
    //*recSymQ /= (sqrtSNR * SQRT_OF_2);

    if (*recSymI < demap256QAM[0]) {
        recBits[0] = 0;
        recBits[1] = 0;
        recBits[2] = 0;
        recBits[3] = 1;
    } else if ((*recSymI >= demap256QAM[0]) && (*recSymI < demap256QAM[1])) {
        recBits[0] = 0;
        recBits[1] = 0;
        recBits[2] = 0;
        recBits[3] = 0;
    } else if ((*recSymI >= demap256QAM[1]) && (*recSymI < demap256QAM[2])) {
        recBits[0] = 0;
        recBits[1] = 0;
        recBits[2] = 1;
        recBits[3] = 0;
    } else if ((*recSymI >= demap256QAM[2]) && (*recSymI < demap256QAM[3])) {
        recBits[0] = 0;
        recBits[1] = 0;
        recBits[2] = 1;
        recBits[3] = 1;
    } else if ((*recSymI >= demap256QAM[3]) && (*recSymI < demap256QAM[4])) {
        recBits[0] = 0;
        recBits[1] = 1;
        recBits[2] = 1;
        recBits[3] = 1;
    } else if ((*recSymI >= demap256QAM[4]) && (*recSymI < demap256QAM[5])) {
        recBits[0] = 0;
        recBits[1] = 1;
        recBits[2] = 1;
        recBits[3] = 0;
    } else if ((*recSymI >= demap256QAM[5]) && (*recSymI < demap256QAM[6])) {
        recBits[0] = 0;
        recBits[1] = 1;
        recBits[2] = 0;
        recBits[3] = 0;
    } else if ((*recSymI >= demap256QAM[6]) && (*recSymI < demap256QAM[7])) {
        recBits[0] = 0;
        recBits[1] = 1;
        recBits[2] = 0;
        recBits[3] = 1;
    } else if ((*recSymI >= demap256QAM[7]) && (*recSymI < demap256QAM[8])) {
        recBits[0] = 1;
        recBits[1] = 1;
        recBits[2] = 0;
        recBits[3] = 1;
    } else if ((*recSymI >= demap256QAM[8]) && (*recSymI < demap256QAM[9])) {
        recBits[0] = 1;
        recBits[1] = 1;
        recBits[2] = 0;
        recBits[3] = 0;
    } else if ((*recSymI >= demap256QAM[9]) && (*recSymI < demap256QAM[10])) {
        recBits[0] = 1;
        recBits[1] = 1;
        recBits[2] = 1;
        recBits[3] = 0;
    } else if ((*recSymI >= demap256QAM[10]) && (*recSymI < demap256QAM[11])) {
        recBits[0] = 1;
        recBits[1] = 1;
        recBits[2] = 1;
        recBits[3] = 1;
    } else if ((*recSymI >= demap256QAM[11]) && (*recSymI < demap256QAM[12])) {
        recBits[0] = 1;
        recBits[1] = 0;
        recBits[2] = 1;
        recBits[3] = 1;
    } else if ((*recSymI >= demap256QAM[12]) && (*recSymI < demap256QAM[13])) {
        recBits[0] = 1;
        recBits[1] = 0;
        recBits[2] = 1;
        recBits[3] = 0;
    } else if ((*recSymI >= demap256QAM[13]) && (*recSymI < demap256QAM[14])) {
        recBits[0] = 1;
        recBits[1] = 0;
        recBits[2] = 0;
        recBits[3] = 0;
    } else if ((*recSymI >= demap256QAM[14])) {
        recBits[0] = 1;
        recBits[1] = 0;
        recBits[2] = 0;
        recBits[3] = 1;
    }

    if (*recSymQ < demap256QAM[0]) {
        recBits[4] = 0;
        recBits[5] = 0;
        recBits[6] = 0;
        recBits[7] = 1;
    } else if ((*recSymQ >= demap256QAM[0]) && (*recSymQ < demap256QAM[1])) {
        recBits[4] = 0;
        recBits[5] = 0;
        recBits[6] = 0;
        recBits[7] = 0;
    } else if ((*recSymQ >= demap256QAM[1]) && (*recSymQ < demap256QAM[2])) {
        recBits[4] = 0;
        recBits[5] = 0;
        recBits[6] = 1;
        recBits[7] = 0;
    } else if ((*recSymQ >= demap256QAM[2]) && (*recSymQ < demap256QAM[3])) {
        recBits[4] = 0;
        recBits[5] = 0;
        recBits[6] = 1;
        recBits[7] = 1;
    } else if ((*recSymQ >= demap256QAM[3]) && (*recSymQ < demap256QAM[4])) {
        recBits[4] = 0;
        recBits[5] = 1;
        recBits[6] = 1;
        recBits[7] = 1;
    } else if ((*recSymQ >= demap256QAM[4]) && (*recSymQ < demap256QAM[5])) {
        recBits[4] = 0;
        recBits[5] = 1;
        recBits[6] = 1;
        recBits[7] = 0;
    } else if ((*recSymQ >= demap256QAM[5]) && (*recSymQ < demap256QAM[6])) {
        recBits[4] = 0;
        recBits[5] = 1;
        recBits[6] = 0;
        recBits[7] = 0;
    } else if ((*recSymQ >= demap256QAM[6]) && (*recSymQ < demap256QAM[7])) {
        recBits[4] = 0;
        recBits[5] = 1;
        recBits[6] = 0;
        recBits[7] = 1;
    } else if ((*recSymQ >= demap256QAM[7]) && (*recSymQ < demap256QAM[8])) {
        recBits[4] = 1;
        recBits[5] = 1;
        recBits[6] = 0;
        recBits[7] = 1;
    } else if ((*recSymQ >= demap256QAM[8]) && (*recSymQ < demap256QAM[9])) {
        recBits[4] = 1;
        recBits[5] = 1;
        recBits[6] = 0;
        recBits[7] = 0;
    } else if ((*recSymQ >= demap256QAM[9]) && (*recSymQ < demap256QAM[10])) {
        recBits[4] = 1;
        recBits[5] = 1;
        recBits[6] = 1;
        recBits[7] = 0;
    } else if ((*recSymQ >= demap256QAM[10]) && (*recSymQ < demap256QAM[11])) {
        recBits[4] = 1;
        recBits[5] = 1;
        recBits[6] = 1;
        recBits[7] = 1;
    } else if ((*recSymQ >= demap256QAM[11]) && (*recSymQ < demap256QAM[12])) {
        recBits[4] = 1;
        recBits[5] = 0;
        recBits[6] = 1;
        recBits[7] = 1;
    } else if ((*recSymQ >= demap256QAM[12]) && (*recSymQ < demap256QAM[13])) {
        recBits[4] = 1;
        recBits[5] = 0;
        recBits[6] = 1;
        recBits[7] = 0;
    } else if ((*recSymQ >= demap256QAM[13]) && (*recSymQ < demap256QAM[14])) {
        recBits[4] = 1;
        recBits[5] = 0;
        recBits[6] = 0;
        recBits[7] = 0;
    } else if ((*recSymQ >= demap256QAM[14])) {
        recBits[4] = 1;
        recBits[5] = 0;
        recBits[6] = 0;
        recBits[7] = 1;
    }
}

int decode_asymbol(float* recSymI, float* recSymQ,
        float* recBits, int bitsPerSymbol) {
    
    switch (bitsPerSymbol) {
        case BPSK: {
            decode_bpsk(recSymI, recSymQ, recBits);
            break;
        }
        case QPSK: {
            decode_qpsk(recSymI, recSymQ, recBits);
            break;
        }
        case QAM16: {
            decode_16qam(recSymI, recSymQ, recBits);
            break;
        }
        case QAM64: {
            decode_64qam(recSymI, recSymQ, recBits);
            break;
        }
        case QAM256: {
            decode_256qam(recSymI, recSymQ, recBits);
            break;
        }
        default: return -1;
    }
    return 0;
}

int decode_symbols(float* rxSymI, float* rxSymQ, int howManySymbols,
        int bitsPerSymbol, float* rxBits) {
    for (int i = 0; i < howManySymbols; i++) {
        decode_asymbol(rxSymI + i, rxSymQ + i,
                    rxBits + i * bitsPerSymbol, bitsPerSymbol);
    }
    return 0;
}



// >> FDM PILOT <<

/* Estimate channel (frequency) transfer function (CTF)
 * at frequency points determined by pilot subcarrier indxes.
 *
 * Parameters
 *  Hi      - CTF I-component
 *  Hq      - CTF Q-component
 *  rxSigI  - Rx symbol sequence I-component
 *  rxSigQ  - Rx symbol sequence Q-component
 *  pltI    - pilot sequence I-component samples
 *  pltQ    - pilot sequence Q-component samples
 *  pltIndx - indexes of pilot subcarriers
 *  pltLen  - pilot sequence length in symbols
 * 
 * >>
 * NOTE: This function can be also used for TDM pilot, but an array
 *       with all indexes (0, 1, ..., numCarriers-1) has tu be provided
 *       in place of pltIndx.
 * >>
 */
void ch_estimation_fdm(float Hi[], float Hq[], float rxSigI[], float rxSigQ[], float pltI[], float pltQ[], int pltIndx[], int pltLen) {
    float tmp;
    int i;
    for (int k = 0; k < pltLen; k++){
        i = pltIndx[k];
        // complex number division
        tmp = (pltI[k]*pltI[k] + pltQ[k]*pltQ[k]);
        Hi[i] = (rxSigI[i]*pltI[k] + rxSigQ[i]*pltQ[k])/tmp;
        Hq[i] = (rxSigQ[i]*pltI[k] - rxSigI[i]*pltQ[k])/tmp;
    }
}


// >> CHANNEL TRANSFER FUNCTION INTERPOLATION <<

/* Function interp_polynomial_N() is a general function that fits
   an arbitrary, order N, polynomial (Lagrange polynomial interpolation).

   Functions interp_linear and interp_quadratic are special cases for
   linear and quadratic interpolation, respectively.

   They are probided as it might be more convenient to let students implement
   these two functions (for which placeholders will be left in code)
*/

/* Linear interpolation of the CTF based on available samples
 * at frequency points determined by pilot subcarrier indxes.
 *
 * Parameters
 *  Hi          - CTF I-component
 *  Hq          - CTF Q-component
 *  pltIndx     - indexes of pilot subcarriers
 *  numCarriers - total number of subcarriers (data + pilots)
 */
void interp_linear(float Hi[], float Hq[], int pltIndx[], int numCarriers, int numPilots) {
    float c_lo, c_hi;  // interpolation coefficients
    int i_lo, i_hi;     // distances from the closest known points (pilots)

    // NOTE: When magnitude and phase are interpolated
    // float H_mag_lo, H_mag_hi, H_mag; // variables for magnitude interpolation
    // float H_arg_lo, H_arg_hi, H_arg; // variables for phase interpolation

    // ensures extrapolation if the 1st carrier is not a pilot
    i_lo = pltIndx[0];
    i_hi = pltIndx[1];

    int k = 0;
    for (int i = 0; i < numCarriers; i++) {
        // skip pilot carriers
        if (i == pltIndx[k]) {
            // prevent overshooting index if the last carrier is not a pilot
            if ( k < numPilots-1 ) k++;

            // closest CTF samples (pilots)
            i_lo = pltIndx[k-1];
            i_hi = pltIndx[k];

            // skip interpolation for pilots
            continue;
        }
        
        // interpolation coefficients
        c_lo = ((float) i_hi-i)/(i_hi-i_lo);
        c_hi = ((float) i-i_lo)/(i_hi-i_lo);

        // interpolate I and Q components
        Hi[i] = c_lo*Hi[i_lo] + c_hi*Hi[i_hi];
        Hq[i] = c_lo*Hq[i_lo] + c_hi*Hq[i_hi];

        /* NOTE
         * This results in high variations in the CTF magnitude, which
         * are smoothed by the noise filtering (based on FFT/IFFT).
         */


        // ALTERNATIVE: interpolate magnitude and phase

        // // linearly interpolate magnitude
        // H_mag_lo = sqrt(Hi[i_lo]*Hi[i_lo] + Hq[i_lo]*Hq[i_lo]);
        // H_mag_hi = sqrt(Hi[i_hi]*Hi[i_hi] + Hq[i_hi]*Hq[i_hi]);
        // H_mag = c_lo*H_mag_lo + c_hi*H_mag_hi;


        // // linearly interpolate phase
        // H_arg_lo = atan2(Hq[i_lo], Hi[i_lo]);
        // H_arg_hi = atan2(Hq[i_hi], Hi[i_hi]);
        // H_arg = c_lo*H_arg_lo + c_hi*H_arg_hi;

        // // get I and Q components from magnitude and phase
        // Hi[i] = H_mag*cos(H_arg);
        // Hq[i] = H_mag*sin(H_arg);

    }
}


/* Second-order polynomial (quadratic) interpolation of the CTF based on
 * available samples at frequency points determined by pilot subcarrier indxes.
 *
 * Parameters
 *  Hi          - CTF I-component
 *  Hq          - CTF Q-component
 *  pltIndx     - indexes of pilot subcarriers
 *  numCarriers - total number of subcarriers (data + pilots)
 */
void interp_quadratic(float Hi[], float Hq[], int pltIndx[], int numCarriers, int numPilots) {
    // Special case of Lagrange interpolating polynomial (i.e. 2nd order)

    float c1, c2, c3; // interpolation coefficients
    int i1, i2, i3;    // distance from the closest pilots
    
    // NOTE: When magnitude and phase are interpolated
    // float H_mag1, H_mag2, H_mag3, H_mag; // variables for magnitude interpolation
    // float H_arg1, H_arg2, H_arg3, H_arg; // variables for phase interpolation

    // ensures extrapolation if the 1st carrier is not a pilot
    i1 = pltIndx[0];
    i2 = pltIndx[1];
    i3 = pltIndx[2];

    int k = 0;
    for (int i = 0; i < numCarriers; i++) {
        // skip pilot carriers
        if (i == pltIndx[k]) {
            // prevent overshooting index if the last carrier is not a pilot
            if ( k < numPilots-2 ) k++;

            // update closest known points indexes
            i1 = pltIndx[k-1];
            i2 = pltIndx[k];
            i3 = pltIndx[k+1];

            // skip interpolation for pilot carriers
            continue;
        }

        c1 = ((float) (i-i2)*(i-i3))/((i1-i2)*(i1-i3));
        c2 = ((float) (i-i1)*(i-i3))/((i2-i1)*(i2-i3));
        c3 = ((float) (i-i1)*(i-i2))/((i3-i1)*(i3-i2));

        // interpolate I and Q components
        Hi[i] = c1*Hi[i1] + c2*Hi[i2] + c3*Hi[i3];
        Hq[i] = c1*Hq[i1] + c2*Hq[i2] + c3*Hq[i3];

        /* NOTE
         * This results in high variations in the CTF magnitude, which
         * are smoothed by the noise filtering (based on FFT/IFFT).
         */


        // ALTERNATIVE: interpolate magnitude and phase
        
        // // linearly interpolate magnitude
        // H_mag1 = sqrt(Hi[i1]*Hi[i1] + Hq[i1]*Hq[i1]);
        // H_mag2 = sqrt(Hi[i2]*Hi[i2] + Hq[i2]*Hq[i2]);
        // H_mag3 = sqrt(Hi[i3]*Hi[i3] + Hq[i3]*Hq[i3]);
        // H_mag = c1*H_mag1 + c2*H_mag2 + c3*H_mag3;


        // // linearly interpolate phase
        // H_arg1 = atan2(Hq[i1], Hi[i1]);
        // H_arg2 = atan2(Hq[i2], Hi[i2]);
        // H_arg3 = atan2(Hq[i3], Hi[i3]);
        // H_arg = c1*H_arg1 + c2*H_arg2 + c3*H_arg3;

        // // get I and Q components from magnitude and phase
        // Hi[i] = H_mag*cos(H_arg);
        // Hq[i] = H_mag*sin(H_arg);

    }
}


/* Interpolate CTF at the given index with the max. order polynomial,
 * for a given number of known samples (len), i.e. order = len-1.
 * Interpolation is applied to the magnitude and phase.
 * 
 * NOTE: This function is called from interp_polynomial_N, which
 *       implements arbitrary order polynomial interpolation. 
 *
 * Parameters
 *  ind   - frame sequence (OFDM symbol) I-component
 *  Hi    - CTF sequence I-component samples
 *  Hq    - CTF sequence Q-component samples
 *  indH  - indexes of known samples in Hi and Hq
 *  len   - length of Hi and Hq (known CTF samples)
 */
void interp_polynomial_mag(int ind, float Hi[], float Hq[], int indH[], int len) {
    float H_mag = 0.0; // CTF magnitude
    float H_arg = 0.0; // CTF phase
    float c;           // sample contribution coefficient
    int i;              // index of sample whose contribution is calculated (in each step)

    for (int j = 0; j < len; j++) {
        // contribution of the j-th pilot to the interpolation
        c = 1.0;
        for (int l = 0; l < len; l++) {
            if (l != j) {
                c *= ((float) ind-indH[l])/(indH[j]-indH[l]);
            }
        }
        
        // magnitude and phase interpolation
        i = indH[j]; // to simplify notation
        H_mag += c*sqrt(Hi[i]*Hi[i] + Hq[i]*Hq[i]);
        H_arg += c*atan2(Hq[i], Hi[i]);
    }

    // get I and Q components from magnitude and phase
    Hi[ind] = H_mag*cos(H_arg);
    Hq[ind] = H_mag*sin(H_arg);
}


/* Interpolate CTF at the given index with the max. length polynomial,
 * for a given number of known samples len, i.e. order = len-1.
 * Interpolation is applied to the I and Q componenets.
 * 
 * NOTE: This function is called from interp_polynomial_N, which
 *       implements arbitrary order polynomial interpolation.
 *
 * Parameters
 *  ind   - frame sequence (OFDM symbol) I-component
 *  Hi    - CTF sequence I-component samples
 *  Hq    - CTF sequence Q-component samples
 *  indH  - indexes of known samples in Hi and Hq
 *  len   - length of Hi and Hq (known CTF samples)
 */
void interp_polynomial_iq(int ind, float Hi[], float Hq[], int indH[], int len) {
    float c; // sample contribution coefficient

    Hi[ind] = 0.0;
    Hq[ind] = 0.0;
    for (int j = 0; j < len; j++) {
        // contribution of the j-th pilot to the interpolation
        c = 1.0;
        for (int l = 0; l < len; l++) {
            if (l != j) {
                c *= ((float) ind-indH[l])/(indH[j]-indH[l]);
            }
        }
        // I and Q components
        Hi[ind] += c*Hi[indH[j]];
        Hq[ind] += c*Hq[indH[j]];
    }
}


/* Arbitrary-order polynomial interpolation of the CTF, based
 * on known CTF samples at provided pilot indexes.
 * Missing values in Hi and Hq are filled in.
 *
 * Parameters
 *  Hi           - CTF sequence I-component samples
 *  Hq           - CTF sequence Q-component samples
 *  pltIndx      - indexes of pilot subcarriers
 *  numCarriers  - total number of subcarriers (data + pilots)
 *  numPilots    - total number of pilots
 *  interp_order - interpolation order (i.e. <= numPilots-1)
 */
int interp_polynomial_N(float Hi[], float Hq[], int pltIndx[], int numCarriers, int numPilots, int interp_order) {
    // maximum interpolation polynomial order is numPilots-1
    if (interp_order > numPilots-1 || interp_order < 1) return EXIT_FAILURE;

    int k = 0;     // index through CTF samples (pilots)
    int k_off = 0; // CTF sample points offset index for interpolation
    int k_min = ((int) (interp_order+1)/2);
    int k_max = numPilots-(interp_order+1);

    for (int i = 0; i < numCarriers; i++) {
        
        if (i == pltIndx[k]) {
            // update index of the 1st interpolation point (CTF sample)
            if ( k >= k_min && k_off < k_max ) k_off++;
            k++;      // update pilot counter
            continue; // skip interpolation for pilots
        }

        // interpolate I and Q components
        interp_polynomial_iq(i, Hi, Hq, pltIndx+k_off, interp_order+1);

        // ALTERNATIVE: interpolate magnitude and phase
        // interp_polynomial_mag(i, Hi, Hq, pltIndx+k_off, interp_order+1);
    }

    return EXIT_SUCCESS;
}


/* High-resolution interpolation based on FFT.
 *
 * Parameters
 *  Hi           - CTF sequence I-component samples
 *  Hq           - CTF sequence Q-component samples
 *  pltIndx      - indexes of pilot subcarriers
 *  numCarriers  - total number of subcarriers (data + pilots)
 *  numPilots    - total number of pilots
 */
// Interpolates the CTF at missing points by high-resolution DFT method.
void interp_fft(float Hi[], float Hq[], int pltIndx[], int numCarriers, int numPilots, 
                fftwf_plan plan_fft_carrier, fftwf_plan plan_ifft_pilot) {
    
    // required as the fft/ifft implementations do not allow for in-place calculation
    float* hi = (float*) calloc(numCarriers, sizeof(float));
    float* hq = (float*) calloc(numCarriers, sizeof(float));

    float complex* carrierCmplx_in = (float complex*) calloc(numCarriers, sizeof(float complex));
    float complex* carrierCmplx_out = (float complex*) calloc(numCarriers, sizeof(float complex));

    float complex* pilotCmplx_in = (float complex*) calloc(numPilots, sizeof(float complex));
    float complex* pilotCmplx_out = (float complex*) calloc(numPilots, sizeof(float complex));

    /*
    Since number of pilots is limited to numCarriers/2, we ca use
    the the two halfs of the same array to calculate IFFT.

    NOTE: Dynamic allocation of memory at each call of this function
          is not the most efficient solution. If instead of numCarriers
          we used SYMBOLS_PER_BLOCK constant defined in OFDM.h, then instead
          of dynamic allocation we could have a regular array (allocated at
          the time of compilation?)
    */

    // mid point index
    int mid = numCarriers/2;

    // copy CTF samples to second half of hi and hq
    for (int i = 0; i < numPilots; i++) {
        hi[mid+i] = Hi[pltIndx[i]];
        hq[mid+i] = Hq[pltIndx[i]];
    }

    // calculate a numPilots-point IFFT and place it in the first half of hi and hq
    generate_complex_symbol(hi + mid, hq + mid, pilotCmplx_in, numPilots);
    fftwf_execute_dft(plan_ifft_pilot, pilotCmplx_in, pilotCmplx_out);

    for (int i = 0; i < numPilots; i++) {
        hi[i] = crealf(pilotCmplx_out[i]) / numPilots;
        hq[i] = cimagf(pilotCmplx_out[i]) / numPilots;
    }
    // set remaining samples to zero
    int th = (numPilots < CP_LEN) ? numPilots: CP_LEN; // min of two numbers
    for (int i = th; i < numCarriers; i++) {
        hi[i] = 0.0;
        hq[i] = 0.0;
    }

    // calculate a numCarriers-point FFT
    generate_complex_symbol(hi, hq, carrierCmplx_in, numCarriers);
    fftwf_execute_dft(plan_fft_carrier, carrierCmplx_in, carrierCmplx_out);

    for (int i = 0; i < numCarriers; i++) {
        Hi[i] = crealf(carrierCmplx_out[i]);
        Hq[i] = cimagf(carrierCmplx_out[i]);
    }

    // free dynamically allocated memory
    free(hi);
    free(hq);

    free(carrierCmplx_in);
    free(carrierCmplx_out);

    free(pilotCmplx_in);
    free(pilotCmplx_out);
}
