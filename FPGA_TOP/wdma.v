

module wdma (
        ap_clk,
        ap_rst_n,
        ap_start,
        ap_done,
        ap_idle,
        ap_ready,
        m_axi_gmem_AWVALID,
        m_axi_gmem_AWREADY,
        m_axi_gmem_AWADDR,
        m_axi_gmem_AWID,
        m_axi_gmem_AWLEN,
        m_axi_gmem_AWSIZE,
        m_axi_gmem_AWBURST,
        m_axi_gmem_AWLOCK,
        m_axi_gmem_AWCACHE,
        m_axi_gmem_AWPROT,
        m_axi_gmem_AWQOS,
        m_axi_gmem_AWREGION,
        m_axi_gmem_AWUSER,
        m_axi_gmem_WVALID,
        m_axi_gmem_WREADY,
        m_axi_gmem_WDATA,
        m_axi_gmem_WSTRB,
        m_axi_gmem_WLAST,
        m_axi_gmem_WID,
        m_axi_gmem_WUSER,
        m_axi_gmem_ARVALID,
        m_axi_gmem_ARREADY,
        m_axi_gmem_ARADDR,
        m_axi_gmem_ARID,
        m_axi_gmem_ARLEN,
        m_axi_gmem_ARSIZE,
        m_axi_gmem_ARBURST,
        m_axi_gmem_ARLOCK,
        m_axi_gmem_ARCACHE,
        m_axi_gmem_ARPROT,
        m_axi_gmem_ARQOS,
        m_axi_gmem_ARREGION,
        m_axi_gmem_ARUSER,
        m_axi_gmem_RVALID,
        m_axi_gmem_RREADY,
        m_axi_gmem_RDATA,
        m_axi_gmem_RLAST,
        m_axi_gmem_RID,
        m_axi_gmem_RUSER,
        m_axi_gmem_RRESP,
        m_axi_gmem_BVALID,
        m_axi_gmem_BREADY,
        m_axi_gmem_BRESP,
        m_axi_gmem_BID,
        m_axi_gmem_BUSER,
        transfer_byte,
        in_r_dout,
        in_r_empty_n,
        in_r_read,
        mem
);
parameter    C_M_AXI_GMEM_ID_WIDTH = 1;
parameter    C_M_AXI_GMEM_ADDR_WIDTH = 32;
parameter    C_M_AXI_GMEM_DATA_WIDTH = 64;
parameter    C_M_AXI_GMEM_AWUSER_WIDTH = 1;
parameter    C_M_AXI_GMEM_ARUSER_WIDTH = 1;
parameter    C_M_AXI_GMEM_WUSER_WIDTH = 1;
parameter    C_M_AXI_GMEM_RUSER_WIDTH = 1;
parameter    C_M_AXI_GMEM_BUSER_WIDTH = 1;

localparam C_M_AXI_GMEM_WSTRB_WIDTH = (C_M_AXI_GMEM_DATA_WIDTH / 8);

input   ap_clk;
input   ap_rst_n;

input   ap_start;
output   ap_done;
output   ap_idle;
output   ap_ready;

output  [C_M_AXI_GMEM_ID_WIDTH - 1:0] m_axi_gmem_AWID;
output  [2:0] m_axi_gmem_AWSIZE;
output  [1:0] m_axi_gmem_AWBURST;
output  [1:0] m_axi_gmem_AWLOCK;
output  [3:0] m_axi_gmem_AWCACHE;
output  [2:0] m_axi_gmem_AWPROT;
output  [3:0] m_axi_gmem_AWQOS;
output  [3:0] m_axi_gmem_AWREGION;
output  [C_M_AXI_GMEM_AWUSER_WIDTH - 1:0] m_axi_gmem_AWUSER;
output  [C_M_AXI_GMEM_ID_WIDTH - 1:0] m_axi_gmem_WID;
output  [C_M_AXI_GMEM_WUSER_WIDTH - 1:0] m_axi_gmem_WUSER;
output  [C_M_AXI_GMEM_WSTRB_WIDTH - 1:0] m_axi_gmem_WSTRB; // full use wdata.
input  [1:0] m_axi_gmem_BRESP;
input  [C_M_AXI_GMEM_ID_WIDTH - 1:0] m_axi_gmem_BID;
input  [C_M_AXI_GMEM_BUSER_WIDTH - 1:0] m_axi_gmem_BUSER;

output   m_axi_gmem_AWVALID;
input   m_axi_gmem_AWREADY;
output  [C_M_AXI_GMEM_ADDR_WIDTH - 1:0] m_axi_gmem_AWADDR;
output  [7:0] m_axi_gmem_AWLEN;

output   m_axi_gmem_WVALID;
input   m_axi_gmem_WREADY;
output  [C_M_AXI_GMEM_DATA_WIDTH - 1:0] m_axi_gmem_WDATA;
output   m_axi_gmem_WLAST;

input   m_axi_gmem_BVALID;
output   m_axi_gmem_BREADY;

output   m_axi_gmem_ARVALID;
input   m_axi_gmem_ARREADY;
output  [C_M_AXI_GMEM_ADDR_WIDTH - 1:0] m_axi_gmem_ARADDR;
output  [C_M_AXI_GMEM_ID_WIDTH - 1:0] m_axi_gmem_ARID;
output  [7:0] m_axi_gmem_ARLEN;
output  [2:0] m_axi_gmem_ARSIZE;
output  [1:0] m_axi_gmem_ARBURST;
output  [1:0] m_axi_gmem_ARLOCK;
output  [3:0] m_axi_gmem_ARCACHE;
output  [2:0] m_axi_gmem_ARPROT;
output  [3:0] m_axi_gmem_ARQOS;
output  [3:0] m_axi_gmem_ARREGION;
output  [C_M_AXI_GMEM_ARUSER_WIDTH - 1:0] m_axi_gmem_ARUSER;
input   m_axi_gmem_RVALID;
output   m_axi_gmem_RREADY;
input  [C_M_AXI_GMEM_DATA_WIDTH - 1:0] m_axi_gmem_RDATA;
input   m_axi_gmem_RLAST;
input  [C_M_AXI_GMEM_ID_WIDTH - 1:0] m_axi_gmem_RID;
input  [C_M_AXI_GMEM_RUSER_WIDTH - 1:0] m_axi_gmem_RUSER;
input  [1:0] m_axi_gmem_RRESP;

input  [C_M_AXI_GMEM_ADDR_WIDTH-1:0] transfer_byte;
input  [C_M_AXI_GMEM_ADDR_WIDTH-1:0] mem; // base address

input  [C_M_AXI_GMEM_DATA_WIDTH-1:0] in_r_dout;
input   in_r_empty_n;
output   in_r_read;


wire  								s_valid;
wire  								s_ready;
wire  [C_M_AXI_GMEM_DATA_WIDTH-1:0] s_data;

assign s_data = in_r_dout;
assign s_valid = in_r_empty_n;
assign in_r_read = s_ready;

localparam S_IDLE 	= 2'b00;
localparam S_RUN 	= 2'b01;
localparam S_PRE 	= 2'b10;  
localparam S_DONE 	= 2'b11;

localparam NUM_SAMPLE_IN_AXI_DATA = C_M_AXI_GMEM_DATA_WIDTH/8; 
localparam AXI_DATA_SHIFT = $clog2(NUM_SAMPLE_IN_AXI_DATA); 
localparam NUM_AXI_AW_MOR_REQ = 8'd4;
localparam LOG_NUM_AXI_AW_MOR_REQ = $clog2(NUM_AXI_AW_MOR_REQ + 1); 

localparam NUM_MAX_BURST = 16;
localparam NUM_AWLEN_BIT = 8;

reg [1:0] 	c_state; 
reg [1:0] 	n_state; 
wire	  	is_run;  
wire	  	is_done;

reg [1:0] 	c_state_aw; 
reg [1:0] 	n_state_aw; 

reg [1:0] 	c_state_w; 
reg [1:0] 	n_state_w; 

reg [1:0] 	c_state_b; 
reg [1:0] 	n_state_b; 

wire w_s_idle;
wire w_s_pre ;
wire w_s_run ;
wire w_s_done;

reg  [C_M_AXI_GMEM_ADDR_WIDTH-1:0] r_transfer_byte; 
reg  [C_M_AXI_GMEM_ADDR_WIDTH-1:0] r_wdma_baseaddr; 

reg tick_ff;

reg	 [C_M_AXI_GMEM_ADDR_WIDTH-1:0] r_real_base_addr;
reg	 [C_M_AXI_GMEM_ADDR_WIDTH-NUM_SAMPLE_IN_AXI_DATA-1:0] r_num_total_stream_hs;

reg	 [C_M_AXI_GMEM_ADDR_WIDTH-NUM_SAMPLE_IN_AXI_DATA-1:0] r_hs_data_cnt;

wire [C_M_AXI_GMEM_ADDR_WIDTH-1:0] wdma_offset_addr;

reg  [C_M_AXI_GMEM_ADDR_WIDTH-1:0] 	 	r_m_axi_gmem_AWADDR;
wire [C_M_AXI_GMEM_ADDR_WIDTH-1:0] 	 	w_m_axi_gmem_AWADDR;

wire aw_hs;
wire w_hs;
wire b_hs;

reg	 [C_M_AXI_GMEM_ADDR_WIDTH-NUM_SAMPLE_IN_AXI_DATA-1:0] r_aw_hs_cnt;
reg	 [C_M_AXI_GMEM_ADDR_WIDTH-NUM_SAMPLE_IN_AXI_DATA-1:0] r_w_hs_cnt;
reg	 [C_M_AXI_GMEM_ADDR_WIDTH-NUM_SAMPLE_IN_AXI_DATA-1:0] r_b_hs_cnt;
wire is_b_last_hs;

wire aw_fifo_full_n;
wire aw_fifo_empty_n;
reg  [NUM_AWLEN_BIT-1:0] r_AWLEN_aw;
reg  [NUM_AWLEN_BIT-1:0] r_burst_len_aw;
wire [NUM_AWLEN_BIT-1:0] burst_len_aw;
wire [NUM_AWLEN_BIT-1:0] AWLEN_w;
wire fifo_read_w;
wire is_last_aw;

wire w_fifo_full_n;
wire w_fifo_empty_n;
wire [NUM_AWLEN_BIT-1:0] AWLEN_b;
wire fifo_read_b;

wire w_s_idle_w;
wire w_s_run_w;
wire is_burst_last_w;
wire is_burst_done_w;
reg	 [NUM_AWLEN_BIT-1:0] r_burst_cnt_w;
reg  [NUM_AWLEN_BIT-1:0] r_burst_len_w;

wire w_s_run_b;
reg  [NUM_AWLEN_BIT-1:0] r_burst_len_b;

reg ap_rst;
always @(posedge ap_clk) begin
  ap_rst <= ~ap_rst_n;
end


assign m_axi_gmem_ARVALID = 'd0;
assign m_axi_gmem_ARREADY = 'd0;
assign m_axi_gmem_ARADDR = 'd0;
assign m_axi_gmem_ARID = 'd0;
assign m_axi_gmem_ARLEN = 'd0;
assign m_axi_gmem_ARSIZE = 'd0;
assign m_axi_gmem_ARBURST = 'd0;
assign m_axi_gmem_ARLOCK = 'd0;
assign m_axi_gmem_ARCACHE = 'd0;
assign m_axi_gmem_ARPROT = 'd0;
assign m_axi_gmem_ARQOS = 'd0;
assign m_axi_gmem_ARREGION = 'd0;
assign m_axi_gmem_ARUSER = 'd0;
assign m_axi_gmem_RREADY = 'd0;

assign m_axi_gmem_AWID			= 1'b0;
assign m_axi_gmem_AWSIZE		= 3'b011; 
assign m_axi_gmem_AWBURST		= 2'b01 ; 
assign m_axi_gmem_AWLOCK		= 2'b0  ;
assign m_axi_gmem_AWCACHE		= 4'b0  ;
assign m_axi_gmem_AWPROT		= 3'b0  ;
assign m_axi_gmem_AWQOS			= 4'b0  ;
assign m_axi_gmem_AWREGION		= 4'b0  ;
assign m_axi_gmem_AWUSER		= 1'b0  ;
assign m_axi_gmem_WID			= 1'b0	;
assign m_axi_gmem_WUSER			= 1'b0	;
assign m_axi_gmem_WSTRB			= {C_M_AXI_GMEM_WSTRB_WIDTH{1'b1}};



always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_transfer_byte		<= 'b0;
		r_wdma_baseaddr	<= 'b0;
	end else if (is_run) begin
		r_transfer_byte		<= transfer_byte; 
		r_wdma_baseaddr	<= mem; 
    end
end


always @(posedge ap_clk) begin
    if(ap_rst) begin
		tick_ff <= 0;
    end else begin
		tick_ff <= ap_start;
    end
end


assign is_run = ap_start & (~tick_ff);
assign is_done = b_hs && is_b_last_hs; 

always @(posedge ap_clk) begin
    if(ap_rst) begin
		c_state <= S_IDLE;
    end else begin
		c_state <= n_state;
    end
end

always @(*) 
begin
	n_state = c_state; 
	case(c_state)
	S_IDLE	: if(is_run)
				n_state = S_PRE;
	S_PRE	: n_state = S_RUN;
	S_RUN 	: if(is_done)
				n_state = S_DONE;
	S_DONE: n_state = S_IDLE;
	endcase
end 

assign w_s_idle 	= (c_state == S_IDLE);
assign w_s_pre 	= (c_state == S_PRE);
assign w_s_run 	= (c_state == S_RUN);
assign w_s_done = (c_state == S_DONE);

assign ap_done = w_s_done;
assign ap_idle = w_s_idle;
assign ap_ready = w_s_pre; 


always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_real_base_addr		<= 'b0;
		r_num_total_stream_hs	<= 'b0;
	end else if (w_s_pre) begin
		r_real_base_addr		<= r_wdma_baseaddr	 	;
		r_num_total_stream_hs	<= r_transfer_byte >> AXI_DATA_SHIFT;
    end
end



wire [C_M_AXI_GMEM_ADDR_WIDTH-NUM_SAMPLE_IN_AXI_DATA-1:0] remain_hs = r_num_total_stream_hs - r_hs_data_cnt;
wire is_max_burst = (remain_hs > NUM_MAX_BURST);
wire [NUM_AWLEN_BIT-1:0] init_burst_len = (is_max_burst) ? NUM_MAX_BURST : remain_hs; 

wire [12:0] addr_4k = 13'h1000;
wire [12-AXI_DATA_SHIFT:0] last_addr_in_burst = (w_m_axi_gmem_AWADDR[11:AXI_DATA_SHIFT] + init_burst_len);
wire [NUM_AWLEN_BIT-1:0] boudary_burst_len_4k = addr_4k[12:AXI_DATA_SHIFT] - w_m_axi_gmem_AWADDR[11:AXI_DATA_SHIFT];
assign is_4k_boundary_burst = (last_addr_in_burst > addr_4k[12:AXI_DATA_SHIFT]);
assign wdma_offset_addr = {r_hs_data_cnt, {AXI_DATA_SHIFT{1'b0}}};

always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_hs_data_cnt	<= 'b0;
	end else if (w_s_idle) begin
		r_hs_data_cnt	<= 'b0;
	end else if (aw_hs) begin
		r_hs_data_cnt	<= r_hs_data_cnt + burst_len_aw;
	end
end

always @(posedge ap_clk) begin
    if(ap_rst) begin
		c_state_aw <= S_IDLE;
    end 
    else begin
		c_state_aw <= n_state_aw;
    end
end

always @(*) 
begin
	n_state_aw = c_state_aw; 
	case(c_state_aw)
	S_IDLE	: if(aw_fifo_full_n & (!is_last_aw) & w_s_run)
			n_state_aw = S_PRE;
	S_PRE	: n_state_aw = S_RUN;
	S_RUN 	: if(aw_hs)
			n_state_aw = S_IDLE;
	endcase
end 

assign w_m_axi_gmem_AWADDR = r_real_base_addr + wdma_offset_addr;

always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_m_axi_gmem_AWADDR	<= 'b0;
		r_AWLEN_aw 			<= 'b0;
		r_burst_len_aw 		<= 'b0;
	end else if (w_s_idle) begin
		r_m_axi_gmem_AWADDR	<= 'b0;
		r_AWLEN_aw 			<= 'b0;
		r_burst_len_aw 		<= 'b0;
	end else if (c_state_aw == S_PRE) begin
		r_m_axi_gmem_AWADDR	<= w_m_axi_gmem_AWADDR;
		r_AWLEN_aw 			<= burst_len_aw - 1'b1;
		r_burst_len_aw 		<= burst_len_aw;
	end
end

assign m_axi_gmem_AWLEN = r_AWLEN_aw;
assign burst_len_aw = (is_4k_boundary_burst)? boudary_burst_len_4k : init_burst_len;
assign is_last_aw = r_aw_hs_cnt >= r_num_total_stream_hs;

assign m_axi_gmem_AWVALID 	= (c_state_aw == S_RUN); 
assign m_axi_gmem_AWADDR	= r_m_axi_gmem_AWADDR;
assign aw_hs = m_axi_gmem_AWVALID & m_axi_gmem_AWREADY;

always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_aw_hs_cnt	<= 'b0;
	end else if (w_s_idle) begin
		r_aw_hs_cnt	<= 'b0;
	end else if (aw_hs) begin
		r_aw_hs_cnt	<= r_aw_hs_cnt + burst_len_aw;
	end
end

sync_fifo 
# (
	.FIFO_IN_REG	(0),
	.FIFO_OUT_REG	(0),
	.FIFO_CMD_LENGTH(NUM_AWLEN_BIT),
	.FIFO_DEPTH     (NUM_AXI_AW_MOR_REQ),
	.FIFO_LOG2_DEPTH(LOG_NUM_AXI_AW_MOR_REQ)
) u_sync_fifo_aw_to_w (
	.clk			(ap_clk),
	.reset			(ap_rst),

	.s_valid		               (aw_hs),
	.s_ready		(aw_fifo_full_n),
	.s_data			(r_burst_len_aw),

	.m_valid		(aw_fifo_empty_n),
	.m_ready		(fifo_read_w),
	.m_data		(AWLEN_w)
);

always @(posedge ap_clk) begin
    if(ap_rst) begin
		c_state_w <= S_IDLE;
    end else begin
		c_state_w <= n_state_w;
    end
end

wire is_aw_req_pre = aw_fifo_empty_n & w_fifo_full_n & w_s_run;
always @(*) 
begin
	n_state_w = c_state_w; 
	case(c_state_w)
	S_IDLE	: if(is_aw_req_pre)
				n_state_w = S_RUN;
	S_RUN 	: if(is_burst_done_w) begin
			n_state_w = S_IDLE;
		           if(is_aw_req_pre) begin
			      n_state_w = S_RUN;
		           end
                            end 
	endcase
end 


assign fifo_read_w = is_burst_done_w; 
assign w_s_idle_w  = (c_state_w == S_IDLE);
assign w_s_run_w   = (c_state_w == S_RUN);


assign is_burst_last_w = (r_burst_cnt_w+1 == AWLEN_w); // 
assign is_burst_done_w = is_burst_last_w & w_hs;

assign m_axi_gmem_WVALID = s_valid;
assign s_ready = m_axi_gmem_WREADY;





assign w_hs = m_axi_gmem_WVALID & m_axi_gmem_WREADY;
assign m_axi_gmem_WDATA = s_data;
assign m_axi_gmem_WLAST = is_burst_last_w;
always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_burst_cnt_w	<= 'b0;
	end else if (w_s_idle_w | is_burst_done_w) begin
		r_burst_cnt_w	<= 'b0;
	end else if (w_hs) begin
		r_burst_cnt_w	<= r_burst_cnt_w + 1'b1;
	end
end

// for counting last W data.
always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_w_hs_cnt	<= 'b0;
	end else if (w_s_idle) begin
		r_w_hs_cnt	<= 'b0;
	end else if (w_hs) begin
		r_w_hs_cnt	<= r_w_hs_cnt + 1'b1;
	end
end

assign is_w_last_hs = (r_w_hs_cnt + 1)  >= r_num_total_stream_hs;

sync_fifo 
# (
	.FIFO_IN_REG	(0),
	.FIFO_OUT_REG	(0),
	.FIFO_CMD_LENGTH(NUM_AWLEN_BIT),
	.FIFO_DEPTH     (NUM_AXI_AW_MOR_REQ),
	.FIFO_LOG2_DEPTH(LOG_NUM_AXI_AW_MOR_REQ)
) u_sync_fifo_w_to_b (
	.clk			(ap_clk),
	.reset			(ap_rst),

	.s_valid		               (is_burst_done_w),
	.s_ready		(w_fifo_full_n),
	.s_data			(AWLEN_w), // 

	.m_valid		(w_fifo_empty_n),
	.m_ready		(fifo_read_b),
	.m_data		(AWLEN_b)
);


always @(posedge ap_clk) begin
    if(ap_rst) begin
		c_state_b <= S_IDLE;
    end else begin
		c_state_b <= n_state_b;
    end
end

always @(*) 
begin
	n_state_b = c_state_b; 
	case(c_state_b)
	S_IDLE	: if(w_fifo_empty_n & w_s_run)
				n_state_b = S_PRE;
	S_PRE	: n_state_b = S_RUN;
	S_RUN 	: if(b_hs)
				n_state_b = S_IDLE;
	endcase
end 

assign fifo_read_b = (c_state_b == S_PRE);
assign w_s_run_b   = (c_state_b == S_RUN);

always @(posedge ap_clk) begin
    if(ap_rst) begin
		r_burst_len_b <= S_IDLE;
    end else if (fifo_read_b) begin
		r_burst_len_b <= AWLEN_b;
    end
end

assign m_axi_gmem_BREADY = w_s_run_b;
assign b_hs = m_axi_gmem_BREADY & m_axi_gmem_BVALID;
assign is_b_last_hs = (r_b_hs_cnt + r_burst_len_b)  >= r_num_total_stream_hs;

always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_b_hs_cnt	<= 'b0;
	end else if (w_s_idle) begin
		r_b_hs_cnt	<= 'b0;
	end else if (b_hs) begin
		r_b_hs_cnt	<= r_b_hs_cnt + r_burst_len_b;
	end
end

endmodule 

