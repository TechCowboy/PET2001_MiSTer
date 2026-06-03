//============================================================================
//  PET2001
//
//  Port to MiSTer
//  Copyright (C) 2017-2019 Sorgelig
//	Extension to Basic v4, 32KB RAM and Loader fix by raparici
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign LED_USER  = tape_led | |drive_led | ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;
assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire [1:0] ar = status[12:11];
video_freak video_freak
(
	.*,
	.VGA_DE_IN(VGA_DE),
	.VGA_DE(),
	.ARX((!ar) ? 12'd4 : (ar - 1'd1)),
	.ARY((!ar) ? 12'd3 : 12'd0),
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.SCALE(status[14:13])
);

localparam NDRIVES=2;

`include "build_id.v" 
localparam CONF_STR = 
{
	"PET2001;;",
	"HAO[20],Drive #8 Type,8250,4040;",
	"H0H2S0,D80D82, Mount #8.0;",
	"H0H2S1,D80D82, Mount #8.1;",
	"H0h2S0,D64, Mount #8.0;",
	"H0h2S1,D64, Mount #8.1;",
	"H0-;",
	"HBO[21],Drive #9 Type,8250,4040;",
	"H1H3S2,D80D82, Mount #9.0;",
	"H1H3S3,D80D82, Mount #9.1;",
	"H1h3S2,D64, Mount #9.0;",
	"H1h3S3,D64, Mount #9.1;",
	"H1-;",
	"F1,TAPPRG;",
	"-;",
	"P1,Hardware;",
	"P1O[17:16],Enable Drive #8,If Mounted,Always,Never;",
	"P1O[19:18],Enable Drive #9,If Mounted,Always,Never;",
	"P1R[15],Reset Drives;",
	"P1-;",
	"P1O78,TAP mode,Fast,Normal,Normal+Sound;",
	"P1O9A,CPU Speed,Normal,x2,x4,x8;",
	"P1O3,Diag,Off,On(needs Reset);",
	"-;",
	"O2,Screen Color,White,Green;",
	"OBC,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O46,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"ODE,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"-;",
	"FC2,ROM,Load System ROM;",
	"-;",
	"R0,Reset;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

localparam CLK = 56_000_000;

wire clk_sys;
wire pll_locked;
		
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

reg reset = 1;
always @(posedge clk_sys) begin
	integer   initRESET = 10000000;
	reg [3:0] reset_cnt;

	if ((!(RESET || status[0] || buttons[1] || (ioctl_download && ioctl_index==2)) && reset_cnt==4'd14) && !initRESET)
		reset <= 0;
	else begin
		if(initRESET) initRESET <= initRESET - 1;
		reset <= 1;
		reset_cnt <= reset_cnt+4'd1;
	end
end

reg  ce_7mp;
reg  ce_7mn;
reg  ce_1m;
wire [6:0] cpu_rates[4] = '{55, 27, 13, 6};

always @(posedge clk_sys) begin
	reg  [2:0] div = 0;
	reg  [6:0] cpu_div = 0;
	reg  [6:0] cpu_rate = 55;

	div <= div + 1'd1;
	ce_7mp  <= !div[2] & !div[1:0];
	ce_7mn  <=  div[2] & !div[1:0];
	
	cpu_div <= cpu_div + 1'd1;
	if(cpu_div == cpu_rate) begin
		cpu_div  <= 0;
		cpu_rate <= (tape_active && !status[8:7]) ? 7'd2 : cpu_rates[status[10:9]];
	end
	ce_1m <= ~(tape_active & ~ram_ready) && !cpu_div;
end


///////////////////////////////////////////////////
// RAM
///////////////////////////////////////////////////

wire ram_ready;
assign DDRAM_CLK = clk_sys;

ddram ram
(
	.*,

	.reset(RESET),
	
	.dout(tape_data),
	.din (ioctl_dout),
	.addr(ioctl_download ? ioctl_addr : tape_addr),
	.we( ioctl_download && ioctl_wr && (ioctl_index == 1)),
	.rd(!ioctl_download && tape_rd),

	.ready(ram_ready)
);

always @(posedge clk_sys) begin
	reg old_ready, old_reset;

	old_ready <= ram_ready;
	old_reset <= reset;

	if(~old_reset && reset) ioctl_wait <= 0;
	if(ioctl_wr && (ioctl_index == 1)) ioctl_wait <= 1;
	else if(ioctl_wait && (~old_ready & ram_ready)) ioctl_wait <= 0;
end


///////////////////////////////////////////////////

localparam NDU = NDRIVES*2;

wire [31:0] status;
wire  [1:0] buttons;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
reg         ioctl_wait = 0;
wire [10:0] ps2_key;
wire        forced_scandoubler;

wire    [31:0] sd_lba[NDU];
wire     [5:0] sd_blk_cnt[NDU];
wire [NDU-1:0] sd_rd;
wire [NDU-1:0] sd_wr;
wire [NDU-1:0] sd_ack;
wire    [12:0] sd_buff_addr;
wire     [7:0] sd_buff_dout;
wire     [7:0] sd_buff_din[NDU];
wire           sd_buff_wr;
wire [NDU-1:0] img_mounted;
wire    [31:0] img_size;
wire           img_readonly;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(NDU), .BLKSZ(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.status(status),
	.status_menumask({
		/* 3 */ status[21], // drive #9 type
		/* 2 */ status[20], // drive #8 type
		/* 1 */ status[19], // drive #9 enabled
		/* 0 */ status[17], // drive #8 enabled
	}),
	.forced_scandoubler(forced_scandoubler),

	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_readonly(img_readonly),

	.ps2_key(ps2_key),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait)
);


///////////////////////////////////////////////////
// CPU
///////////////////////////////////////////////////

wire [15:0] addr;
wire  [7:0] cpu_data_out;
wire  [7:0] cpu_data_in;
wire        rnw;

wire we = ~rnw;
wire irq;

T65 cpu
(
    .Mode(0),
    .Res_n(~reset),
    .Enable(ce_1m),
    .Clk(clk_sys),
    .Rdy(1),
    .Abort_n(1),
    .IRQ_n(~irq),
    .NMI_n(1),
    .SO_n(1),
    .R_W_n(rnw),
    .A(addr),
    .DI(cpu_data_in),
    .DO(cpu_data_out)
);


///////////////////////////////////////////////////
// Commodore Pet hardware
///////////////////////////////////////////////////

wire pix;
wire HSync, VSync;
wire audioDat;

assign CLK_VIDEO = clk_sys;
wire HBlank, VBlank;

pet2001hw hw
(
	.*,
	.clk(clk_sys),

	.data_out(cpu_data_in),
	.data_in(cpu_data_out),

	.cass_motor_n(),
	.cass_write(tape_write),
	.audio(audioDat),
	.cass_sense_n(0),
	.cass_read(tape_audio),
	.diag_l(!status[3]),
	
	.ieee_i(ieee_bus_te),
	.ieee_o(ieee_bus_dc),

	.dma_addr(dl_addr),
	.dma_din(dl_data),
	.dma_dout(),
	.dma_we(dl_wr),

	.clk_speed(0),
	.clk_stop(0)
);


////////////////////////////////////////////////////////////////////
// Loading
////////////////////////////////////////////////////////////////////

reg  [15:0] dl_addr;
reg   [7:0] dl_data;
reg         dl_wr;

always @(posedge clk_sys) begin
	reg        old_download = 0;
	reg  [3:0] state = 0;
	reg [15:0] addr;

	dl_wr <= 0;
	old_download <= ioctl_download;

	if(ioctl_download && (ioctl_index == 8'h41)) begin
		state <= 0;
		if(ioctl_wr) begin  
			     if(ioctl_addr == 0) addr[7:0]  <= ioctl_dout;
			else if(ioctl_addr == 1) addr[15:8] <= ioctl_dout;
			else begin
				if(addr<'h8000) begin
					dl_addr <= addr;
					dl_data <= ioctl_dout;
					dl_wr   <= 1;
					addr    <= addr + 1'd1;
				end
			end
		end
	end

	if(old_download && ~ioctl_download && (ioctl_index == 8'h41)) state <= 1;
	if(state) state <= state + 1'd1;

	case(state)
		 1: begin dl_addr <= 16'h2a; dl_data <= addr[7:0];  dl_wr <= 1; end
		 3: begin dl_addr <= 16'h2b; dl_data <= addr[15:8]; dl_wr <= 1; end
	endcase
	
	if(ioctl_download && ioctl_index==2) begin
		state <= 0;
		if(ioctl_wr) begin
			if(ioctl_addr<'h8000) begin
				dl_addr <= {1'b1,ioctl_addr[14:0]};
				dl_data <= ioctl_dout;
				dl_wr   <= 1;
			end
		end
	end
end

wire [2:0] scale = status[6:4];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0; 
assign VGA_SL = sl[1:0];
assign VGA_F1 = 0;


////////////////////////////////////////////////////////////////////
// Video
////////////////////////////////////////////////////////////////////	

video_mixer #(.HALF_DEPTH(1)) video_mixer
(
	.*,
	.ce_pix(ce_7mp),
	
	.scandoubler(scale || forced_scandoubler),
	.hq2x(scale==1),
	.gamma_bus(),
	.freeze_sync(),

	.R({4{~status[2] & pix}}),
	.G({4{pix}}),
	.B({4{~status[2] & pix}})
);

 
////////////////////////////////////////////////////////////////////
// Audio
////////////////////////////////////////////////////////////////////		

wire [1:0] audio = {audioDat ^ tape_write, tape_audio & tape_active & (status[8:7] == 2)};
assign AUDIO_L = {audio, 12'd0};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;
assign AUDIO_MIX = 0;

wire        tape_audio;
wire        tape_rd;
wire [24:0] tape_addr;
wire  [7:0] tape_data;
wire        tape_pause = 0;
wire        tape_active;
wire        tape_write;

tape tape(.*, .clk(clk_sys), .ioctl_download(ioctl_download && (ioctl_index==1)));

reg [18:0] act_cnt;
wire       tape_led = act_cnt[18] ? act_cnt[17:10] <= act_cnt[7:0] : act_cnt[17:10] > act_cnt[7:0];
always @(posedge clk_sys) if((|status[8:7] ? ce_1m : ce_7mp) && (tape_active || act_cnt[18] || act_cnt[17:0])) act_cnt <= act_cnt + 1'd1; 

//////////////////////////////////////////////////////////////////////
// IEEE Drives
//////////////////////////////////////////////////////////////////////

st_ieee_bus ieee_bus_te;
st_ieee_bus ieee_bus_dc;

wire drive_reset = reset | status[15];
wire [1:0] drive_led;

reg [3:0] drive_mounted = 0;
always @(posedge clk_sys) begin 
	if(img_mounted[0]) drive_mounted[0] <= |img_size;
	if(img_mounted[1]) drive_mounted[1] <= |img_size;
	if(img_mounted[2]) drive_mounted[2] <= |img_size;
	if(img_mounted[3]) drive_mounted[3] <= |img_size;
end

ieee_drive #(.DRIVES(NDRIVES)) ieee_drive
(
	.*,
	.CLK(CLK),

	.reset({drive_reset | ((!status[19:18]) ? !drive_mounted[3:2] : status[19]),
		     drive_reset | ((!status[17:16]) ? !drive_mounted[1:0] : status[17])}),

	.pause(1'b0),

	.led(drive_led),

	.bus_i(ieee_bus_dc),
	.bus_o(ieee_bus_te),

	.drv_type(status[21:20]),

	.rom_wr(0),
	.rom_sel(0),
	.rom_addr(0),
	.rom_data(0)
);

//////////////////////////////////////////////////////////////////////
// PS/2 to PET keyboard interface
//////////////////////////////////////////////////////////////////////
wire [7:0] 	keyin;
wire [3:0] 	keyrow;	 
wire        shift_lock;

keyboard keyboard(.*, .clk(clk_sys), .Fn(), .mod());

endmodule

module sram
(
	input        clk,

	input [15:0] addr,
	input  [7:0] din,
	input        we,
	output reg [7:0] dout
);

reg [7:0] data[65536];

always @(posedge clk) begin
	if(we) begin
		data[addr] <= din;
		dout <= din;
	end else begin
		dout <= data[addr];
	end
end

endmodule
