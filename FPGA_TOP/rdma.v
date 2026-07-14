
module rdma (
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
        mem,
        out_r_din,
        out_r_full_n,
        out_r_write
);
parameter C_M_AXI_GMEM_ID_WIDTH     = 1;
parameter C_M_AXI_GMEM_ADDR_WIDTH   = 32;
parameter C_M_AXI_GMEM_DATA_WIDTH   = 64;
parameter C_M_AXI_GMEM_AWUSER_WIDTH = 1;
parameter C_M_AXI_GMEM_ARUSER_WIDTH = 1;
parameter C_M_AXI_GMEM_WUSER_WIDTH  = 1;
parameter C_M_AXI_GMEM_RUSER_WIDTH  = 1;
parameter C_M_AXI_GMEM_BUSER_WIDTH  = 1;

localparam C_M_AXI_GMEM_WSTRB_WIDTH  = (C_M_AXI_GMEM_DATA_WIDTH / 8);

input  ap_clk;
input  ap_rst_n;


input  ap_start;
output ap_done;
output ap_idle;
output ap_ready;


output m_axi_gmem_AWVALID;
input  m_axi_gmem_AWREADY;
output [C_M_AXI_GMEM_ADDR_WIDTH - 1:0] m_axi_gmem_AWADDR;
output [C_M_AXI_GMEM_ID_WIDTH - 1:0] m_axi_gmem_AWID;
output [7:0] m_axi_gmem_AWLEN;
output [2:0] m_axi_gmem_AWSIZE;
output [1:0] m_axi_gmem_AWBURST;
output [1:0] m_axi_gmem_AWLOCK;
output [3:0] m_axi_gmem_AWCACHE;
output [2:0] m_axi_gmem_AWPROT;
output [3:0] m_axi_gmem_AWQOS;
output [3:0] m_axi_gmem_AWREGION;
output [C_M_AXI_GMEM_AWUSER_WIDTH - 1:0] m_axi_gmem_AWUSER;
output m_axi_gmem_WVALID;
input  m_axi_gmem_WREADY;
output [C_M_AXI_GMEM_DATA_WIDTH - 1:0] m_axi_gmem_WDATA;
output [C_M_AXI_GMEM_WSTRB_WIDTH - 1:0] m_axi_gmem_WSTRB;
output m_axi_gmem_WLAST;
output [C_M_AXI_GMEM_ID_WIDTH - 1:0] m_axi_gmem_WID;
output [C_M_AXI_GMEM_WUSER_WIDTH - 1:0] m_axi_gmem_WUSER;
input  m_axi_gmem_BVALID;
output m_axi_gmem_BREADY;
input  [1:0] m_axi_gmem_BRESP;
input  [C_M_AXI_GMEM_ID_WIDTH - 1:0] m_axi_gmem_BID;
input  [C_M_AXI_GMEM_BUSER_WIDTH - 1:0] m_axi_gmem_BUSER;

output [C_M_AXI_GMEM_ID_WIDTH - 1:0] m_axi_gmem_ARID;
output [2:0] m_axi_gmem_ARSIZE;
output [1:0] m_axi_gmem_ARBURST;
output [1:0] m_axi_gmem_ARLOCK;
output [3:0] m_axi_gmem_ARCACHE;
output [2:0] m_axi_gmem_ARPROT;
output [3:0] m_axi_gmem_ARQOS;
output [3:0] m_axi_gmem_ARREGION;
input  [C_M_AXI_GMEM_ID_WIDTH - 1:0] m_axi_gmem_RID;
input  [C_M_AXI_GMEM_RUSER_WIDTH - 1:0] m_axi_gmem_RUSER;
output [C_M_AXI_GMEM_ARUSER_WIDTH - 1:0] m_axi_gmem_ARUSER;
input  [1:0] m_axi_gmem_RRESP;


output m_axi_gmem_ARVALID;
input  m_axi_gmem_ARREADY;
output [C_M_AXI_GMEM_ADDR_WIDTH - 1:0] m_axi_gmem_ARADDR;
output [7:0] m_axi_gmem_ARLEN;

input  m_axi_gmem_RVALID;
output m_axi_gmem_RREADY;
input  [C_M_AXI_GMEM_DATA_WIDTH - 1:0] m_axi_gmem_RDATA;
input  m_axi_gmem_RLAST;


input  [31:0] transfer_byte;
input  [31:0] mem; 


output [C_M_AXI_GMEM_DATA_WIDTH-1:0] out_r_din;
input  out_r_full_n;
output out_r_write;


wire  								m_valid;
wire  								m_ready;
wire  [C_M_AXI_GMEM_DATA_WIDTH-1:0] m_data;

assign out_r_din = m_data;
assign out_r_write = m_valid;
assign m_ready = out_r_full_n;

localparam S_IDLE 	= 2'b00;
localparam S_RUN 	= 2'b01;
localparam S_PRE 	= 2'b10;  
localparam S_DONE 	= 2'b11;

localparam NUM_SAMPLE_IN_AXI_DATA = C_M_AXI_GMEM_DATA_WIDTH/8; // 64 bit
localparam AXI_DATA_SHIFT = $clog2(NUM_SAMPLE_IN_AXI_DATA); // 2^3 
localparam NUM_AXI_AR_MOR_REQ = 8'd4;
localparam LOG_NUM_AXI_AR_MOR_REQ = $clog2(NUM_AXI_AR_MOR_REQ) + 1;

localparam NUM_MAX_BURST = 16;
localparam NUM_ARLEN_BIT = 8;

reg [1:0] 	c_state; 
reg [1:0] 	n_state; 
wire	  	is_run;  
wire	  	is_done;

reg [1:0] 	c_state_ar; 
reg [1:0] 	n_state_ar; 

reg [1:0] 	c_state_r; 
reg [1:0] 	n_state_r; 

wire w_s_idle;
wire w_s_pre ;
wire w_s_run ;
wire w_s_done;


reg  [31:0] r_transfer_byte; 
reg  [31:0] r_rdma_baseaddr; 

reg tick_ff;

reg	 [31:0] r_real_base_addr;
reg	 [31-NUM_SAMPLE_IN_AXI_DATA:0] r_num_total_stream_hs;

reg	 [31-NUM_SAMPLE_IN_AXI_DATA:0] r_hs_data_cnt;

wire [31:0] rdma_offset_addr;

reg  [C_M_AXI_GMEM_ADDR_WIDTH-1:0] 	 	r_m_axi_gmem_ARADDR;
wire [C_M_AXI_GMEM_ADDR_WIDTH-1:0] 	 	w_m_axi_gmem_ARADDR;

wire ar_hs;
wire r_hs;

reg	 [31-NUM_SAMPLE_IN_AXI_DATA:0] r_ar_hs_cnt;
reg	 [31-NUM_SAMPLE_IN_AXI_DATA:0] r_r_hs_cnt;
wire is_r_last_hs;

wire ar_fifo_full_n;
wire ar_fifo_empty_n;
reg  [NUM_ARLEN_BIT-1:0] r_ARLEN_ar;
reg  [NUM_ARLEN_BIT-1:0] r_burst_len_ar;
wire [NUM_ARLEN_BIT-1:0] burst_len_ar;
wire [NUM_ARLEN_BIT-1:0] ARLEN_r;
wire fifo_read_r;
wire is_last_ar;

wire w_s_idle_r;
wire is_burst_done_r;
reg	 [NUM_ARLEN_BIT-1:0] r_burst_cnt_r;

reg ap_rst;

always @(posedge ap_clk) begin
  ap_rst <= ~ap_rst_n;
end


assign m_axi_gmem_AWVALID  = 'd0;
assign m_axi_gmem_AWADDR   = 'd0;
assign m_axi_gmem_AWID     = 'd0;
assign m_axi_gmem_AWLEN    = 'd0;
assign m_axi_gmem_AWSIZE   = 'd0;
assign m_axi_gmem_AWBURST  = 'd0;
assign m_axi_gmem_AWLOCK   = 'd0;
assign m_axi_gmem_AWCACHE  = 'd0;
assign m_axi_gmem_AWPROT   = 'd0;
assign m_axi_gmem_AWQOS    = 'd0;
assign m_axi_gmem_AWREGION = 'd0;
assign m_axi_gmem_AWUSER   = 'd0;
assign m_axi_gmem_WVALID   = 'd0;
assign m_axi_gmem_WDATA    = 'd0;
assign m_axi_gmem_WSTRB    = 'd0;
assign m_axi_gmem_WLAST    = 'd0;
assign m_axi_gmem_WID      = 'd0;
assign m_axi_gmem_WUSER    = 'd0;
assign m_axi_gmem_BREADY   = 'd0;

assign m_axi_gmem_ARID     = 1'b0 ;
assign m_axi_gmem_ARSIZE   = 3'b011;
assign m_axi_gmem_ARBURST  = 2'b01 ; 
assign m_axi_gmem_ARLOCK   = 2'b0 ;
assign m_axi_gmem_ARCACHE  = 4'b0 ;
assign m_axi_gmem_ARPROT   = 3'b0 ;
assign m_axi_gmem_ARQOS    = 4'b0 ;
assign m_axi_gmem_ARREGION = 4'b0 ;
assign m_axi_gmem_ARUSER   = 1'b0 ;

always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_transfer_byte			<= 'b0;
		r_rdma_baseaddr		<= 'b0;
	end else if (is_run) begin
		r_transfer_byte			<= transfer_byte; 
		r_rdma_baseaddr		<= mem; // base address
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
assign is_done = r_hs & is_r_last_hs & m_axi_gmem_RLAST;

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
	S_DONE	: n_state = S_IDLE;
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
		r_real_base_addr		<= r_rdma_baseaddr	 	;
		r_num_total_stream_hs	<= r_transfer_byte >> AXI_DATA_SHIFT;
    end
end


wire [31-NUM_SAMPLE_IN_AXI_DATA:0] remain_hs = r_num_total_stream_hs - r_hs_data_cnt;
wire is_max_burst = (remain_hs > NUM_MAX_BURST);
wire [NUM_ARLEN_BIT-1:0] init_burst_len = (is_max_burst) ? NUM_MAX_BURST : remain_hs; 

wire [12:0] addr_4k = 13'h1000;
wire [12-AXI_DATA_SHIFT:0] last_addr_in_burst = (w_m_axi_gmem_ARADDR[11:AXI_DATA_SHIFT] + init_burst_len);
wire [NUM_ARLEN_BIT-1:0] boudary_burst_len_4k = addr_4k[12:AXI_DATA_SHIFT] - w_m_axi_gmem_ARADDR[11:AXI_DATA_SHIFT];
assign is_4k_boundary_burst = (last_addr_in_burst > addr_4k[12:AXI_DATA_SHIFT]);
assign rdma_offset_addr = {r_hs_data_cnt, {AXI_DATA_SHIFT{1'b0}}};

always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_hs_data_cnt	<= 'b0;
	end else if (w_s_idle) begin
		r_hs_data_cnt	<= 'b0;
	end else if (ar_hs) begin
		r_hs_data_cnt	<= r_hs_data_cnt + burst_len_ar;
	end
end

always @(posedge ap_clk) begin
    if(ap_rst) begin
		c_state_ar <= S_IDLE;
    end else begin
		c_state_ar <= n_state_ar;
    end
end

always @(*) 
begin
	n_state_ar = c_state_ar; 
	case(c_state_ar)
	S_IDLE	: if(ar_fifo_full_n & (!is_last_ar) & w_s_run)
				n_state_ar = S_PRE;
	S_PRE	: n_state_ar = S_RUN;
	S_RUN 	: if(ar_hs)
				n_state_ar = S_IDLE;
	endcase
end 

assign w_m_axi_gmem_ARADDR = r_real_base_addr + rdma_offset_addr;

always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_m_axi_gmem_ARADDR	<= 'b0;
		r_ARLEN_ar 			<= 'b0;
		r_burst_len_ar 		<= 'b0;
	end else if (w_s_idle) begin
		r_m_axi_gmem_ARADDR	<= 'b0;
		r_ARLEN_ar 			<= 'b0;
		r_burst_len_ar 		<= 'b0;
	end else if (c_state_ar == S_PRE) begin
		r_m_axi_gmem_ARADDR	<= w_m_axi_gmem_ARADDR;
		r_ARLEN_ar 			<= burst_len_ar - 1'b1;
		r_burst_len_ar 		<= burst_len_ar;
	end
end


assign m_axi_gmem_ARLEN = r_ARLEN_ar;
assign burst_len_ar = (is_4k_boundary_burst)? boudary_burst_len_4k : init_burst_len;
assign is_last_ar = r_ar_hs_cnt >= r_num_total_stream_hs;

assign m_axi_gmem_ARVALID	= c_state_ar == S_RUN;
assign m_axi_gmem_ARADDR	= r_m_axi_gmem_ARADDR;
assign ar_hs = m_axi_gmem_ARVALID & m_axi_gmem_ARREADY;

always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_ar_hs_cnt	<= 'b0;
	end else if (w_s_idle) begin
		r_ar_hs_cnt	<= 'b0;
	end else if (ar_hs) begin
		r_ar_hs_cnt	<= r_ar_hs_cnt + burst_len_ar;
	end
end

sync_fifo 
# (
	.FIFO_IN_REG	(0),
	.FIFO_OUT_REG	(0),
	.FIFO_CMD_LENGTH(NUM_ARLEN_BIT),
	.FIFO_DEPTH     (NUM_AXI_AR_MOR_REQ),
	.FIFO_LOG2_DEPTH(LOG_NUM_AXI_AR_MOR_REQ)
) u_sync_fifo (
	.clk		(ap_clk),
	.reset		(ap_rst),

	.s_valid		(ar_hs),
	.s_ready	(ar_fifo_full_n),
	.s_data		(r_burst_len_ar),

	.m_valid	(ar_fifo_empty_n),
	.m_ready	(fifo_read_r),
	.m_data	(ARLEN_r)
);


always @(posedge ap_clk) begin
    if(ap_rst) begin
		c_state_r <= S_IDLE;
    end else begin
		c_state_r <= n_state_r;
    end
end

always @(*) 
begin
	n_state_r = c_state_r; 
	case(c_state_r)
	S_IDLE	: if(ar_fifo_empty_n)
				n_state_r = S_RUN;
	S_RUN 	: if(is_burst_done_r) begin
					if(ar_fifo_empty_n) begin
						n_state_r = S_RUN;
					end else begin
						n_state_r = S_IDLE;
					end
			  end  
	endcase
end 

assign is_burst_done_r = m_axi_gmem_RLAST & r_hs;
assign fifo_read_r = (c_state_r == S_RUN) & is_burst_done_r;
assign w_s_idle_r  = (c_state_r == S_IDLE);


assign m_axi_gmem_RREADY = m_ready;
assign m_valid = m_axi_gmem_RVALID;
assign r_hs = m_axi_gmem_RVALID & m_axi_gmem_RREADY;
assign m_data = m_axi_gmem_RDATA;
always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_burst_cnt_r	<= 'b0;
	end else if (w_s_idle_r | is_burst_done_r) begin
		r_burst_cnt_r	<= 'b0;
	end else if (r_hs) begin
		r_burst_cnt_r	<= r_burst_cnt_r + 1'b1;
	end
end


always @(posedge ap_clk) begin
	if(ap_rst) begin
		r_r_hs_cnt	<= 'b0;
	end else if (w_s_idle) begin
		r_r_hs_cnt	<= 'b0;
	end else if (r_hs) begin
		r_r_hs_cnt	<= r_r_hs_cnt + 1'b1;
	end
end

assign is_r_last_hs = r_r_hs_cnt == (r_num_total_stream_hs-1);

endmodule


