//#include <pluto.h>
#include "pluto.h"


bool stop_signal = false;
char tmpstr[64];

int sockfd;
struct sockaddr_in saddr;

int main (int argc, char** argv)
{
	//UDP transmission initialization
	sockfd = socket(AF_INET,SOCK_DGRAM,0);
	assert( sockfd != -1 );
	memset(&saddr,0,sizeof(saddr));
	saddr.sin_family = AF_INET;
	saddr.sin_port = htons(9090);
	saddr.sin_addr.s_addr = inet_addr("192.168.188.28");
	


	bool tx_flag =false;
	bool rx_flag =false;
	bool both_flag =false;

	
	if (argc < 2) {
        usage(argv[0]);
        return (EXIT_FAILURE);
    }

	tx_flag = !strcmp(argv[1], "t") || !strcmp(argv[1], "T") || !strcmp(argv[1], "tx") || !strcmp(argv[1], "TX");
	rx_flag = !strcmp(argv[1], "r") || !strcmp(argv[1], "R") || !strcmp(argv[1], "rx") || !strcmp(argv[1], "RX");
	both_flag = !strcmp(argv[1], "b") || !strcmp(argv[1], "B") || !strcmp(argv[1], "both") || !strcmp(argv[1], "BOTH");

	if(!(tx_flag || rx_flag || both_flag))
	{
		usage(argv[0]);
        return (EXIT_FAILURE);
	}

	//================= Create Threads for receiving and processing signals ========================================

	thread_argument_ptr_t argument = thread_argument_init(rx_flag);
	if(argument == NULL) { fprintf(stderr, "Thread argument inilization failed!\n"); return -1; }
	
	// Listen to ctrl+c
	signal(SIGINT, handle_sig);

	pthread_t thread_0, thread_1_1;

	if(tx_flag || both_flag)
	{
		pthread_create(&thread_0, NULL, thread_function_0, (void *) argument);
		printf("\n\t* Start transmitting\n");
	}
	
	if(rx_flag || both_flag)
	{
		pthread_create(&thread_1_1, NULL, thread_function_1_1, (void *) argument);
		printf("\n\t* Start receiving\n");
	}

	//----------------------------- Join threads -----------------------------
	if(tx_flag || both_flag)
	{
		pthread_join(thread_0, NULL);
		printf("\n\t* Stop TX thread\n");
	}
    
	if(rx_flag || both_flag)
	{
		pthread_join(thread_1_1, NULL);
		printf("\n\t* Stop RX threads\n");
	}
	
    thread_argument_free(argument);

	//Ethernet_Client_Close();
	close(sockfd);

	return 0;
}
