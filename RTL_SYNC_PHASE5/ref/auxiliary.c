#include "pluto.h"


int save_result_success(double BER, char* fileName) {
    FILE* fptr = fopen(fileName, "a");

	fprintf(fptr, "\n\t%s", "BER = ");
    fprintf(fptr, "%.2f", BER);
	fprintf(fptr, "%s\n", "%");
    fclose(fptr);

    return 0;
}

int save_result_fail(char* fileName) {
    FILE* fptr = fopen(fileName, "a");

    fprintf(fptr, "\n\t%s\n", "Signal Detection Failed!");
    fclose(fptr);

    return 0;
}

int save_signal(float complex* signal_cmplx, int len, char* fileName) {
    FILE* fptr = fopen(fileName, "w");

    for (int k = 0; k < len; k++) {
        fprintf(fptr, "%f\t%f\t\n", crealf(signal_cmplx[k]), cimagf(signal_cmplx[k]));
    }
    fclose(fptr);

    return 0;
}


int clear_file(char* fileName) {

    FILE* fptr = fopen(fileName, "w");

    fclose(fptr);

    return 0;
}

void usage(char* programName) {
    printf("\nUsage:\n%s   <Transceiving mode - transmit only> [ t/T/tx/TX ]\n"
			"\nOR\n"
			"\n%s   <Transceiving mode - receive only> [ r/R/rx/RX ]\n"
            "\nOR\n"
			"\n%s   <Transceiving mode - transmit and receive> [ b/B/both/BOTH ]\n\n", programName, programName, programName);
}

void handle_sig(int sig) {
	printf("Waiting for process to finish... Got signal %d\n", sig);
	stop_signal = true;
}

void complex_multiplication(double* inI1, double* inQ1, double* inI2, double* inQ2, double* outI, double* outQ)
{
	double P1 = (*inI1) * (*inI2);
	double P2 = (*inQ1) * (*inQ2);
	double P3 = ((*inI1) + (*inQ1)) * ((*inI2) + (*inQ2));

	*outI = P1 - P2;
	*outQ = P3 - P2 - P1;
}

void generate_complex_symbol(float* inI, float* inQ, float complex* outCmplx, size_t len){
	for(int i = 0; i < len; i++){
		outCmplx[i] = inI[i] + inQ[i] * I;
	}
}

int save_asignal(float* t, float* signal, int len, char* fileName) {
    FILE* fptr = fopen(fileName, "w");

    for (int k = 0; k < len; k++) {
        fprintf(fptr, "%f\t%f\t\n", t[k], signal[k]);
    }
    fclose(fptr);

    return 0;
}

int save_1column(float* signal, int len, char* fileName) {
    FILE* fptr = fopen(fileName, "w");

    for (int k = 0; k < len; k++) {
        fprintf(fptr, "%f\t\n", signal[k]);
    }
    fclose(fptr);

    return 0;
}

int save_1row(float* signal, int len, char* fileName) {
    FILE* fptr = fopen(fileName, "w");

    for (int k = 0; k < len; k++) {
        fprintf(fptr, "%f\t", signal[k]);
    }
    fclose(fptr);

    return 0;
}