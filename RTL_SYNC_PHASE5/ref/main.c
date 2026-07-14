// main.c
#include "pluto.h"
#include <signal.h>
#include <assert.h>
#include <errno.h>

// === 전역 변수 정의(단 한 곳: main.c) ===
// pluto.h에는 반드시 extern 선언만 있어야 합니다.
bool stop_signal = false;
char tmpstr[64];

int sockfd = -1;
struct sockaddr_in saddr = {0};

// SIGINT 핸들러는 pluto.h 또는 다른 소스에 이미 있다면 중복 정의 금지
// 여기서는 선언만 가정
extern void handle_sig(int);

static void usage_and_exit(const char *prog)
{
    fprintf(stderr,
        "Usage: %s [t|r|b]\n"
        "  t : transmit only\n"
        "  r : receive only\n"
        "  b : both (tx+rx)\n", prog);
    exit(EXIT_FAILURE);
}

// WSL에서 mDNS/Avahi가 꺼져있어 자동검색이 실패하므로,
// IIOD_REMOTE가 비어 있으면 기본 IP로 채워준다.
static void ensure_iio_remote_env(void)
{
    const char *remote = getenv("IIOD_REMOTE");
    if (!remote || !remote[0]) {
        // 기본값: Pluto의 RNDIS 기본 주소
        setenv("IIOD_REMOTE", "192.168.2.1", 0); // 이미 있으면 유지(0)
    }
}

int main (int argc, char** argv)
{
    // ----- 인자 검사 -----
    if (argc < 2) {
        usage_and_exit(argv[0]);
    }

    const char *mode = argv[1];
    bool tx_flag   = (!strcmp(mode, "t") || !strcmp(mode, "T") || !strcmp(mode, "tx")   || !strcmp(mode, "TX"));
    bool rx_flag   = (!strcmp(mode, "r") || !strcmp(mode, "R") || !strcmp(mode, "rx")   || !strcmp(mode, "RX"));
    bool both_flag = (!strcmp(mode, "b") || !strcmp(mode, "B") || !strcmp(mode, "both") || !strcmp(mode, "BOTH"));

    if (!(tx_flag || rx_flag || both_flag)) {
        usage_and_exit(argv[0]);
    }

    // ----- IIO 네트워크 컨텍스트를 환경변수로 강제 -----
    ensure_iio_remote_env();

    // ----- UDP 소켓 초기화 -----
    sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd < 0) {
        perror("socket");
        return EXIT_FAILURE;
    }

    memset(&saddr, 0, sizeof(saddr));
    saddr.sin_family = AF_INET;
    saddr.sin_port   = htons(9090);
    // ★ 여기 IP는 여러분의 수신측(UDP)을 넣으세요. (예시 IP 그대로 사용 중)
    //   필요 시 argv로 받도록 확장 가능.
    saddr.sin_addr.s_addr = inet_addr("192.168.188.28");
    if (saddr.sin_addr.s_addr == INADDR_NONE) {
        fprintf(stderr, "ERROR: invalid UDP destination IP\n");
        close(sockfd);
        return EXIT_FAILURE;
    }

    // ----- 스레드 인자 생성 (rx_flag는 기존 시그니처 유지) -----
    thread_argument_ptr_t argument = thread_argument_init(rx_flag);
    if (argument == NULL) {
        fprintf(stderr, "Thread argument initialization failed!\n");
        close(sockfd);
        return EXIT_FAILURE;
    }

    // ----- Ctrl+C 처리 -----
    signal(SIGINT, handle_sig);

    pthread_t thread_tx, thread_rx;
    int rc;

    // ----- TX 스레드 -----
    if (tx_flag || both_flag) {
        rc = pthread_create(&thread_tx, NULL, thread_function_0, (void *)argument);
        if (rc != 0) {
            fprintf(stderr, "pthread_create(TX) failed: %s\n", strerror(rc));
            thread_argument_free(argument);
            close(sockfd);
            return EXIT_FAILURE;
        }
        printf("\n\t* Start transmitting\n");
    }

    // ----- RX 스레드 -----
    if (rx_flag || both_flag) {
        rc = pthread_create(&thread_rx, NULL, thread_function_1_1, (void *)argument);
        if (rc != 0) {
            fprintf(stderr, "pthread_create(RX) failed: %s\n", strerror(rc));
            // TX가 이미 올라갔다면 기다렸다가 정리
            if (tx_flag || both_flag) {
                pthread_join(thread_tx, NULL);
                printf("\n\t* Stop TX thread (due to RX failure)\n");
            }
            thread_argument_free(argument);
            close(sockfd);
            return EXIT_FAILURE;
        }
        printf("\n\t* Start receiving\n");
    }

    // ----- Join -----
    if (tx_flag || both_flag) {
        pthread_join(thread_tx, NULL);
        printf("\n\t* Stop TX thread\n");
    }
    if (rx_flag || both_flag) {
        pthread_join(thread_rx, NULL);
        printf("\n\t* Stop RX thread\n");
    }

    thread_argument_free(argument);
    close(sockfd);
    return 0;
}

