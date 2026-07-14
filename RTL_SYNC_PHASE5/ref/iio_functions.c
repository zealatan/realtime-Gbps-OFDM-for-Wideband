//#include <pluto.h>
#include "pluto.h"
#include <stdlib.h>
#include <stdio.h>

/* -------------------------
   안전한 네트워크 컨텍스트 생성
   ------------------------- */
static struct iio_context* create_ctx_network(void) {
    const char *remote = getenv("IIOD_REMOTE");
    if (!remote || !remote[0]) remote = "192.168.2.1";

    struct iio_context *ctx = iio_create_network_context(remote);
    if (!ctx) {
        fprintf(stderr, "ERROR: Failed to create IIO network context to %s\n", remote);
        return NULL;
    }
    return ctx;
}

/* -------------------------
   Pluto 초기화 (스캔/자동검색 제거)
   ------------------------- */
Pluto_cfg_ptr_t Pluto_init(bool rx_flag)
{
    Pluto_cfg_ptr_t pluto = malloc(sizeof(struct Pluto_config_structure));
    if (!pluto) {
        fprintf(stderr, "ERROR: malloc Pluto_config_structure\n");
        return NULL;
    }
    memset(pluto, 0, sizeof(*pluto));

    printf("* Acquiring IIO context\n");
    pluto->ctx = create_ctx_network();
    IIO_ENSURE(pluto->ctx && "No context");

    IIO_ENSURE(iio_context_get_devices_count(pluto->ctx) > 0 && "No devices");

    long long bb_sampling_rate = MHZ(20);

    /* RX PHY */
    pluto->rx_phy.bw_hz     = MHZ(50);
    pluto->rx_phy.lo_hz     = GHZ(2.450);
    pluto->rx_phy.rfport    = "A_BALANCED";
    pluto->rx_phy.gain_ctrl = "slow_attack";
    pluto->rx_phy.fs_hz     = bb_sampling_rate;

    /* TX PHY */
    pluto->tx_phy.bw_hz   = MHZ(50);
    pluto->tx_phy.lo_hz   = GHZ(2.450);
    pluto->tx_phy.rfport  = "A";
    pluto->tx_phy.hw_gain = -5.0;
    pluto->tx_phy.pwr_down = rx_flag ? 1 : 0;   /* RX만 할 때 TX 파워다운 */

    /* BB rate 설정 (libad9361) */
    ad9361_set_bb_rate(get_ad9361_phy(pluto->ctx), pluto->rx_phy.fs_hz);
    ad9361_set_bb_rate(get_ad9361_phy(pluto->ctx), pluto->tx_phy.fs_hz);

    printf("* Configuring AD9361 physical parameters\n");
    if (!cfg_ad9361_rx_phy_ch(pluto, 0)) { fprintf(stderr, "RX port 0 not found\n"); goto FAIL; }
    if (!cfg_ad9361_tx_phy_ch(pluto, 0)) { fprintf(stderr, "TX port 0 not found\n"); goto FAIL; }

    /* 스트리밍 디바이스 */
    printf("* Acquiring AD9361 streaming devices\n");
    if (!get_ad9361_rx_stream_dev(pluto->ctx, &(pluto->rx_stream_dev))) { fprintf(stderr, "No rx dev found\n"); goto FAIL; }
    if (!get_ad9361_tx_stream_dev(pluto->ctx, &(pluto->tx_stream_dev))) { fprintf(stderr, "No tx dev found\n"); goto FAIL; }

    printf("* Initializing AD9361 IIO streaming channels\n");

    if (!get_ad9361_rx_stream_ch(pluto->rx_stream_dev, 0, &(pluto->rx_stream_channel_i))) {
        fprintf(stderr, "RX channel i not found\n"); goto FAIL;
    }
    if (!get_ad9361_rx_stream_ch(pluto->rx_stream_dev, 1, &(pluto->rx_stream_channel_q))) {
        fprintf(stderr, "RX channel q not found\n"); goto FAIL;
    }
    if (!get_ad9361_tx_stream_ch(pluto->tx_stream_dev, 0, &(pluto->tx_stream_channel_i))) {
        fprintf(stderr, "TX channel i not found\n"); goto FAIL;
    }
    if (!get_ad9361_tx_stream_ch(pluto->tx_stream_dev, 1, &(pluto->tx_stream_channel_q))) {
        fprintf(stderr, "TX channel q not found\n"); goto FAIL;
    }

    printf("* Enabling IIO streaming channels\n");
    iio_channel_enable(pluto->rx_stream_channel_i);
    iio_channel_enable(pluto->rx_stream_channel_q);
    iio_channel_enable(pluto->tx_stream_channel_i);
    iio_channel_enable(pluto->tx_stream_channel_q);

    return pluto;

FAIL:
    shutdown_pluto(pluto);
    return NULL;
}

/* -------------------------
   (삭제됨) getURI: 스캔/자동검색 제거
   필요 시 항상 IIOD_REMOTE 또는 192.168.2.1 사용
   ------------------------- */

/* helper function generating channel names */
char* get_ch_name(const char* type, int id)
{
    snprintf(tmpstr, sizeof(tmpstr), "%s%d", type, id);
    return tmpstr;
}

/* cleanup and exit */
void shutdown_pluto(Pluto_cfg_ptr_t pluto)
{
    if (!pluto) return;

    printf("* Disabling streaming channels\n");
    if (pluto->rx_stream_channel_i) iio_channel_disable(pluto->rx_stream_channel_i);
    if (pluto->rx_stream_channel_q) iio_channel_disable(pluto->rx_stream_channel_q);
    if (pluto->tx_stream_channel_i) iio_channel_disable(pluto->tx_stream_channel_i);
    if (pluto->tx_stream_channel_q) iio_channel_disable(pluto->tx_stream_channel_q);

    printf("* Destroying context\n");
    if (pluto->ctx_info) iio_context_info_list_free(pluto->ctx_info);  /* ctx_info는 scan 쓸 때만 생김 */
    if (pluto->scan_ctx) iio_scan_context_destroy(pluto->scan_ctx);    /* 이번 버전엔 생성 안 함(호환 가드) */
    if (pluto->ctx)      iio_context_destroy(pluto->ctx);

    free(pluto);
}

/* write attribute: long long int */
bool wr_ch_lli(struct iio_channel *chn, const char* what, long long val) {
    int rc = iio_channel_attr_write_longlong(chn, what, val);
    if (rc < 0) {
        fprintf(stderr, "Error %d writing LLI attr \"%s\" (val=%lld)\n", rc, what, val);
        return false;
    }
    return true;
}

/* write attribute: double */
bool wr_ch_double(struct iio_channel *chn, const char* what, double val) {
    int rc = iio_channel_attr_write_double(chn, what, val);
    if (rc < 0) {
        fprintf(stderr, "Error %d writing DOUBLE attr \"%s\" (val=%f)\n", rc, what, val);
        return false;
    }
    return true;
}

/* write attribute: string */
bool wr_ch_str(struct iio_channel *chn, const char* what, const char* str) {
    int rc = iio_channel_attr_write(chn, what, str);
    if (rc < 0) {
        fprintf(stderr, "Error %d writing STR attr \"%s\" (val=%s)\n", rc, what, str);
        return false;
    }
    return true;
}

/* -------------------------
   PHY DEVICES AND CHANNELS
   ------------------------- */

/* returns ad9361 phy device */
struct iio_device* get_ad9361_phy(struct iio_context *ctx) {
    struct iio_device *dev = iio_context_find_device(ctx, "ad9361-phy");
    IIO_ENSURE(dev && "No ad9361-phy found");
    return dev;
}

/* finds AD9361 phy IIO configuration channel with id chid */
bool get_rx_phy_chan(struct iio_context *ctx, int chid, struct iio_channel **chn) {
    *chn = iio_device_find_channel(get_ad9361_phy(ctx), get_ch_name("voltage", chid), false);
    return *chn != NULL;
}

bool get_tx_phy_chan(struct iio_context *ctx, int chid, struct iio_channel **chn) {
    *chn = iio_device_find_channel(get_ad9361_phy(ctx), get_ch_name("voltage", chid), true);
    return *chn != NULL;
}

/* finds AD9361 local oscillator IIO configuration channels
   (펌웨어 버전에 따라 altvoltage0/1의 TX/RX 매핑이 다른 경우가 있습니다.
    LO가 뒤바뀌면 0/1을 서로 바꿔보세요.) */
bool get_rx_lo_chan(struct iio_context *ctx, struct iio_channel **chn) {
    *chn = iio_device_find_channel(get_ad9361_phy(ctx), get_ch_name("altvoltage", 0), true);
    return *chn != NULL;
}
bool get_tx_lo_chan(struct iio_context *ctx, struct iio_channel **chn) {
    *chn = iio_device_find_channel(get_ad9361_phy(ctx), get_ch_name("altvoltage", 1), true);
    return *chn != NULL;
}

/* configure physical channel parameters */
bool cfg_ad9361_rx_phy_ch(Pluto_cfg_ptr_t pluto, int chid) {
    struct iio_channel *chn = NULL;

    printf("* Acquiring AD9361 RX phy channel %d\n", chid);
    if (!get_rx_phy_chan(pluto->ctx, chid, &chn)) return false;
    if (!wr_ch_str(chn, "rf_port_select", pluto->rx_phy.rfport)) return false;
    if (!wr_ch_lli(chn, "rf_bandwidth",  pluto->rx_phy.bw_hz))  return false;
    if (!wr_ch_str(chn, "gain_control_mode", pluto->rx_phy.gain_ctrl)) return false;
    // RX hardwaregain은 gain_control_mode가 manual일 때만 사용

    printf("* Acquiring AD9361 RX LO channel\n");
    if (!get_rx_lo_chan(pluto->ctx, &chn)) return false;
    if (!wr_ch_lli(chn, "frequency", pluto->rx_phy.lo_hz)) return false;
    return true;
}

bool cfg_ad9361_tx_phy_ch(Pluto_cfg_ptr_t pluto, int chid) {
    struct iio_channel *chn = NULL;

    printf("* Acquiring AD9361 TX phy channel %d\n", chid);
    if (!get_tx_phy_chan(pluto->ctx, chid, &chn)) return false;
    if (!wr_ch_str(chn, "rf_port_select", pluto->tx_phy.rfport)) return false;
    if (!wr_ch_lli(chn, "rf_bandwidth",  pluto->tx_phy.bw_hz))  return false;
    if (!wr_ch_double(chn, "hardwaregain", pluto->tx_phy.hw_gain)) return false;

    printf("* Acquiring AD9361 TX LO channel\n");
    if (!get_tx_lo_chan(pluto->ctx, &chn)) return false;
    if (!wr_ch_lli(chn, "frequency", pluto->tx_phy.lo_hz)) return false;
    if (!wr_ch_double(chn, "powerdown", pluto->tx_phy.pwr_down)) return false;
    return true;
}

/* -------------------------
   STREAMING DEVICES & CHANS
   ------------------------- */

bool get_ad9361_rx_stream_dev(struct iio_context *ctx, struct iio_device **dev) {
    *dev = iio_context_find_device(ctx, "cf-ad9361-lpc");
    return *dev != NULL;
}
bool get_ad9361_tx_stream_dev(struct iio_context *ctx, struct iio_device **dev) {
    *dev = iio_context_find_device(ctx, "cf-ad9361-dds-core-lpc");
    return *dev != NULL;
}

bool get_ad9361_rx_stream_ch(struct iio_device *dev, int chid, struct iio_channel **chn) {
    *chn = iio_device_find_channel(dev, get_ch_name("voltage", chid), false);
    if (!*chn) *chn = iio_device_find_channel(dev, get_ch_name("altvoltage", chid), false);
    return *chn != NULL;
}
bool get_ad9361_tx_stream_ch(struct iio_device *dev, int chid, struct iio_channel **chn) {
    *chn = iio_device_find_channel(dev, get_ch_name("voltage", chid), true);
    if (!*chn) *chn = iio_device_find_channel(dev, get_ch_name("altvoltage", chid), true);
    return *chn != NULL;
}

