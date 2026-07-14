#include "pluto.h"

//=================================================== Multi Threading Functions =============================

void *thread_function_0(void *thread_arg)	//thread function for displaying BER result
{

    thread_argument_ptr_t arg;
    arg = (thread_argument_ptr_t) thread_arg;

	void *p_dat, *p_end, *p_start;
	ptrdiff_t p_inc;
	
	// WRITE: Get pointers to TX buf and write IQ to TX buf port 0
	p_inc = iio_buffer_step(arg->buf.pluto_tx_buffer);
	p_end = iio_buffer_end(arg->buf.pluto_tx_buffer);
	p_start = iio_buffer_first(arg->buf.pluto_tx_buffer, arg->pluto->tx_stream_channel_i);

	int16_t temp_i, temp_q;

	for (p_dat = p_start; p_dat < p_end; p_dat += p_inc) 
	{
		temp_i = (int16_t)(arg->sig->tx_I[(int)((p_dat-p_start)/p_inc)] * 12000); 	// Real (I)
		temp_q = (int16_t)(arg->sig->tx_Q[(int)((p_dat-p_start)/p_inc)] * 12000); 	// Imag (Q)
		
		((int16_t*)p_dat)[0] = temp_i;
		((int16_t*)p_dat)[1] = temp_q;

	}

	// Schedule TX buffer
	ssize_t nbytes_tx = iio_buffer_push(arg->buf.pluto_tx_buffer);
	if (nbytes_tx < 0) { printf("Error: pushing to buffer %d\n", (int) nbytes_tx); arg->stop_all_threads = true; }

    while((!stop_signal) && (!(arg->stop_all_threads))){}

    pthread_exit(NULL);
}

void *thread_function_1_1(void *thread_arg)	
//thread function for refilling Pluto RX Buffer and copying samples from [RX Pluto Buffer] to [Ring Buffer 1 I/Q]
{

    thread_argument_ptr_t arg;
    arg = (thread_argument_ptr_t) thread_arg;

    while((!stop_signal) && (!(arg->stop_all_threads)))
    {
		clock_t begin = clock();
		
		// Refill RX buffer
		ssize_t nbytes_rx;
		nbytes_rx = iio_buffer_refill(arg->buf.pluto_rx_buffer);
		if (nbytes_rx < 0) { printf("Error refilling buf %d\n", (int)nbytes_rx); arg->stop_all_threads = true; }

		//copying samples from [RX Pluto Buffer] to [Buffer 1 I/Q]
		iio_channel_read(arg->pluto->rx_stream_channel_i, arg->buf.pluto_rx_buffer, 
						arg->buf.signal_processing_buffer_I, 2 * arg->sig->total_slot_len * sizeof(int16_t));
		
		iio_channel_read(arg->pluto->rx_stream_channel_q, arg->buf.pluto_rx_buffer, 
						arg->buf.signal_processing_buffer_Q, 2 * arg->sig->total_slot_len * sizeof(int16_t));

		for(int i = 0; i < 2 * arg->sig->total_slot_len; i++) {
			arg->sig->rx_I[i] = (float)(arg->buf.signal_processing_buffer_I[i]);
			arg->sig->rx_Q[i] = (float)(arg->buf.signal_processing_buffer_Q[i]);
		}

		process_received_slot(arg->sig);
		
		clock_t end = clock();
		double time_spent = (double)(end - begin) / CLOCKS_PER_SEC;
		printf("\n\tRunning time is %f sec.", time_spent);
		printf("\n=======================================================================\n");

    }

    pthread_exit(NULL);
}
