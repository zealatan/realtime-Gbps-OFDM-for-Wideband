#include "pluto.h"


//=================================================== Buffer Functions ===========================================

thread_argument_ptr_t thread_argument_init(bool rx_flag)
{
	thread_argument_ptr_t arg = malloc(sizeof(struct thread_argument_structure));

	arg->pluto = Pluto_init(rx_flag);
	if(arg->pluto == NULL) { return NULL; }

	arg->sig = signal_processing_parameters_init();
	if(arg->sig == NULL) { return NULL; }
	generate_transmit_slot(arg->sig);
	arg->sig->samplingFreq = arg->pluto->rx_phy.fs_hz;

	arg->buf.pluto_tx_buffer = iio_device_create_buffer(arg->pluto->tx_stream_dev, arg->sig->total_slot_len, true);	
	//cyclic buffer
	arg->buf.pluto_rx_buffer = iio_device_create_buffer(arg->pluto->rx_stream_dev, 2 * arg->sig->total_slot_len, false);

	arg->buf.signal_processing_buffer_I = (int16_t*) malloc(2 * arg->sig->total_slot_len * sizeof(int16_t));
	arg->buf.signal_processing_buffer_Q = (int16_t*) malloc(2 * arg->sig->total_slot_len * sizeof(int16_t));
	
	arg->buf.plotting_buffer_after_I = (double*) malloc(arg->sig->total_slot_len * sizeof(double));
	arg->buf.plotting_buffer_after_Q = (double*) malloc(arg->sig->total_slot_len * sizeof(double));

	//=======================================================================================
	thread_argument_reset(arg);
	printf("* Thread argument has been initialized\n");

	return arg;
}

void thread_argument_reset(thread_argument_ptr_t arg)
{
	arg->stop_all_threads = false;

}

void thread_argument_free(thread_argument_ptr_t arg)
{
	free(arg->buf.signal_processing_buffer_I);
	free(arg->buf.signal_processing_buffer_Q);
	free(arg->buf.plotting_buffer_after_I);
	free(arg->buf.plotting_buffer_after_Q);
	if (arg->buf.pluto_tx_buffer) { iio_buffer_destroy(arg->buf.pluto_tx_buffer); }
	if (arg->buf.pluto_rx_buffer) { iio_buffer_destroy(arg->buf.pluto_rx_buffer); }

	signal_processing_parameters_free(arg->sig);

	shutdown_pluto(arg->pluto);

	free(arg);

	printf("* Freeing thread argument resources\n");

}
