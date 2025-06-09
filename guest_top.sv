//============================================================================
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
//
//============================================================================

module guest_top
(
	input         CLOCK_27,
`ifdef USE_CLOCK_50
	input         CLOCK_50,
`endif

	output        LED,
	output [VGA_BITS-1:0] VGA_R,
	output [VGA_BITS-1:0] VGA_G,
	output [VGA_BITS-1:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,

`ifdef USE_HDMI
	output        HDMI_RST,
	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_PCLK,
	output        HDMI_DE,
	inout         HDMI_SDA,
	inout         HDMI_SCL,
	input         HDMI_INT,
`endif

	input         SPI_SCK,
	inout         SPI_DO,
	input         SPI_DI,
	input         SPI_SS2,    // data_io
	input         SPI_SS3,    // OSD
	input         CONF_DATA0, // SPI_SS for user_io

`ifdef USE_QSPI
	input         QSCK,
	input         QCSn,
	inout   [3:0] QDAT,
`endif
`ifndef NO_DIRECT_UPLOAD
	input         SPI_SS4,
`endif

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	output        AUDIO_L,
	output        AUDIO_R,
`ifdef I2S_AUDIO
	output        I2S_BCK,
	output        I2S_LRCK,
	output        I2S_DATA,
`endif
`ifdef I2S_AUDIO_HDMI
	output        HDMI_MCLK,
	output        HDMI_BCK,
	output        HDMI_LRCK,
	output        HDMI_SDATA,
`endif
`ifdef SPDIF_AUDIO
	output        SPDIF,
`endif
`ifdef USE_AUDIO_IN
	input         AUDIO_IN,
`endif
`ifdef USE_MIDI_PINS
	output        MIDI_OUT,
	input         MIDI_IN,
`endif
`ifdef SIDI128_EXPANSION
	input         UART_CTS,
	output        UART_RTS,
	inout         EXP7,
	inout         MOTOR_CTRL,
`endif
	input         UART_RX,
	output        UART_TX
);

`ifdef NO_DIRECT_UPLOAD
localparam bit DIRECT_UPLOAD = 0;
wire SPI_SS4 = 1;
`else
localparam bit DIRECT_UPLOAD = 1;
`endif

`ifdef USE_QSPI
localparam bit QSPI = 1;
assign QDAT = 4'hZ;
`else
localparam bit QSPI = 0;
`endif

`ifdef VGA_8BIT
localparam VGA_BITS = 8;
`else
localparam VGA_BITS = 6;
`endif

`ifdef USE_HDMI
localparam bit HDMI = 1;
assign HDMI_RST = 1'b1;
`else
localparam bit HDMI = 0;
`endif

`ifdef BIG_OSD
localparam bit BIG_OSD = 1;
`define SEP "-;",
`else
localparam bit BIG_OSD = 0;
`define SEP
`endif

`include "build_id.v" 
localparam CONF_STR = {
	"Gigatron;;",
	"-;",
//	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"-;",
	"OAC,Keyboard language,US,GB,DE,FR,IT,ES;",
	"-;",
	"T0,Reset;",
//	"J1,A,B,Select,Start;",
//	"jn,A,B,Select,Start;",
	"V,Poseidon-",`BUILD_DATE 
};

wire forced_scandoubler;
wire scandoubler = (scale || forced_scandoubler);
wire scandoubler_disable;

wire no_csync;

wire  [1:0] buttons;
wire  [1:0] switches;
wire [31:0] status;
wire [10:0] ps2_key = {key_strobe, key_pressed, key_extended, key_code};
wire [15:0] joystick;
wire caps_lock;

wire ps2_kbd_clk,ps2_kbd_data;
wire ps2_mouse_clk,ps2_mouse_data;

wire        key_pressed;
wire [7:0]  key_code;
wire        key_strobe;
wire        key_extended;

wire [31:0] sd_lba;
wire  [1:0] sd_rd;
wire  [1:0] sd_wr;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        sd_ack_conf;
wire        sd_busy;
wire        sd_sdhc;
wire        sd_conf;

wire  [1:0] img_mounted;
wire  [1:0] img_readonly;
wire [63:0] img_size;

wire reset = status[0] | buttons[1];
wire [2:0] scale = status[5:3];

user_io #(.STRLEN($size(CONF_STR)>>3), .SD_IMAGES(1), .PS2DIV(500), .FEATURES(32'h0 | (BIG_OSD << 13) | (HDMI << 14))) user_io
(	
	.clk_sys          (clk_app          ),
	.clk_sd           (clk_sys          ),
	.conf_str         (CONF_STR         ),
	.SPI_CLK          (SPI_SCK          ),
	.SPI_SS_IO        (CONF_DATA0       ),
	.SPI_MISO         (SPI_DO           ),
	.SPI_MOSI         (SPI_DI           ),
	.buttons          (buttons          ),
	.switches         (switches         ),
	.no_csync         (1'b1             ),
	.ypbpr            (            ),

	.ps2_kbd_clk      (ps2_kbd_clk      ),
	.ps2_kbd_data     (ps2_kbd_data     ),
	.key_strobe       (key_strobe       ),
	.key_pressed      (key_pressed      ),
	.key_extended     (key_extended     ),
	.key_code         (key_code         ),
	.joystick_0       (joystick         ),

	.status           (status           ),
	.scandoubler_disable(1'b1),

`ifdef USE_HDMI
	.i2c_start        (i2c_start        ),
	.i2c_read         (i2c_read         ),
	.i2c_addr         (i2c_addr         ),
	.i2c_subaddr      (i2c_subaddr      ),
	.i2c_dout         (i2c_dout         ),
	.i2c_din          (i2c_din          ),
	.i2c_ack          (i2c_ack          ),
	.i2c_end          (i2c_end          ),
`endif
	
//// SD CARD
   .sd_lba           (sd_lba           ),
	.sd_rd            (sd_rd            ),
	.sd_wr            (sd_wr            ),
	.sd_ack           (sd_ack           ),
	.sd_ack_conf      (sd_ack_conf      ),
	.sd_conf          (sd_conf          ),
	.sd_sdhc          (1'b1             ),
	.sd_dout          (sd_buff_dout     ),
	.sd_din           (sd_buff_din      ),
	.sd_buff_addr     (sd_buff_addr     ),
	.sd_dout_strobe   (sd_buff_wr       ),
   .img_mounted      (img_mounted      ),
	.img_size         (img_size         )
);

wire        ioctl_downl;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

data_io data_io(
	.clk_sys       ( clk_sys        ),
	.SPI_SCK       ( SPI_SCK      ),
	.SPI_SS2       ( SPI_SS2      ),
	.SPI_DI        ( SPI_DI       ),
	.ioctl_download( ioctl_downl  ),
	.ioctl_index   ( ioctl_index  ),
	.ioctl_wr      ( ioctl_wr     ),
	.ioctl_addr    ( ioctl_addr   ),
	.ioctl_dout    ( ioctl_dout   )
);


///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
wire clk_vid;
wire clk_app;
wire pll_locked;


pll pll (
	.areset(0),
	.inclk0(CLOCK_50),
	.c0(clk_sys),       //50Mhz
	.c1(clk_vid),       //25Mhz
	.c2(clk_app)        //6.25Mhz
);


//////////////////////////////  MAIN CORE CONNECTIONS  ////////////////////////////////////

wire vsync_n;
wire hsync_n;
wire [1:0] red;
wire [1:0] green;
wire [1:0] blue;
wire hblank, vblank;

wire [7:0] gigatron_output_port;
wire [15:0] audio;

wire famicom_latch;
wire famicom_pulse;
wire famicom_data;

Gigatron_Shell gigatron_shell(
    .fpga_clock(clk_sys), // 50Mhz FPGA clock
    .vga_clock(clk_vid),      // 25Mhz VGA clock from the PLL
    .clock(clk_app), // 6.25Mhz Gigatron clock from the PLL
    .reset(reset),
    .run(1'b1),

    .gigatron_output_port(gigatron_output_port),
    //.gigatron_extended_output_port(gigatron_extended_output_port),
    
    //
    // These signals are from the Famicom serial game controller.
    //
    .famicom_pulse(famicom_pulse), // output
    .famicom_latch(famicom_latch), // output
    .famicom_data(famicom_data),   // input

    //// Raw VGA signals from the Gigatron

    .hsync_n(hsync_n),
    .vsync_n(vsync_n),
    .red(red),
    .green(green),
    .blue(blue),
    .hblank(hblank),
    .vblank(vblank),

    ////
    //// Write output to external framebuffer
    ////
    //// Note: Gigatron outputs its 6.25Mhz clock as the clock
    //// to synchronize these signals.
    ////
    //// The output is standard 8 bit true color with RRRGGGBB.
    ////
    //// https://en.wikipedia.org/wiki/8-bit_color
    ////
    ////    .framebuffer_write_clock(framebuffer_write_clock),
    ////    .framebuffer_write_signal(framebuffer_write_signal),
    ////    .framebuffer_write_address(framebuffer_write_address),
    ////    .framebuffer_write_data(framebuffer_write_data),

    //// BlinkenLights
//        .led5(LED_POWER[0]),
//        .led6(LED_DISK[0]),
//        .led7(LED_USER),
    ////    .led8(gigatron_led8),

    //// 16 bit LPCM audio output from the Gigatron.
    .audio_dac(audio),
    ////    // Digital volume control with range 0 - 11.
    .digital_volume_control(4'd11),

    //// Signals from user interface to select program to load
    //.loader_go(buttons[1]),  // input, true when user select load
    .loader_program_select(4'd0)
    //.loader_active(application_active) // output
);	

//////////////////////////////  VIDEO  ////////////////////////////////////

wire ypbpr;


mist_video #(.COLOR_DEPTH(8), .SD_HCNT_WIDTH(12), .OUT_COLOR_DEPTH(6), .BIG_OSD(BIG_OSD)) mist_video(
	.clk_sys          (clk_vid          ),
	.SPI_SCK          (SPI_SCK          ),
	.SPI_SS3          (SPI_SS3          ),
	.SPI_DI           (SPI_DI           ),
	.R                ({red,red,red,red}),
	.G                ({green,green,green,green}),
	.B                ({blue,blue,blue,blue}),
	.HSync            (hsync_n          ),
	.VSync            (vsync_n          ),
	.HBlank           (hblank           ),
	.VBlank           (vblank           ),
	.VGA_R            (VGA_R            ),
	.VGA_G            (VGA_G            ),
	.VGA_B            (VGA_B            ),
	.VGA_VS           (VGA_VS           ),
	.VGA_HS           (VGA_HS           ),
	.ce_divider       (1'b0             ),
	.no_csync         (1'b1             ),
	.scandoubler_disable(1'b1           ),
	.ypbpr            (1'b0             ),
	.scanlines        (scale            ),
	.rotate           (2'b00            ),
	.blend            (1'b0             )
);

//////////////////////////////  AUDIO  ////////////////////////////////////

assign AUDIO_L = audio;
assign AUDIO_R = audio;


`ifdef I2S_AUDIO
wire [31:0] clk_rate = 32'd25_000_000;

i2s i2s (
    .reset(reset),
    .clk(clk_vid),
    .clk_rate(clk_rate),

    .sclk(I2S_BCK),
    .lrclk(I2S_LRCK),
    .sdata(I2S_DATA),

    .left_chan({1'b0, audio[15:1]}),
    .right_chan({1'b0, audio[15:1]})
);
`endif

////////////////////////////  INPUT  //////////////////////////////////////

reg [7:0] joypad_bits;
reg joypad_clock, last_joypad_clock;
reg joypad_out;

wire [7:0] nes_joy_A = { 
    joystick[0], joystick[1], joystick[2], joystick[3],
    joystick[7], joystick[6], joystick[5], joystick[4] 
};

reg [7:0] ascii_code;

wire [7:0] ascii_bitmap = {
	ascii_code[0], ascii_code[1], ascii_code[2], ascii_code[3],
	ascii_code[4], ascii_code[5], ascii_code[6], ascii_code[7],
};

Keyboard keyboard(
    .kb_lang(status[12:10]),
    .ps2_key(ps2_key),
    .pulse(clk_app),
    .reset(reset),
    .caps_lock(caps_lock),
    .ascii_code(ascii_code)
);

always @(posedge clk_app) begin
	if (reset) begin
		joypad_bits <= 0;
		last_joypad_clock <= 0;
	end else begin
		if (joypad_out) begin
			joypad_bits  <= ~(nes_joy_A | ~ascii_bitmap);
		end
		if (!joypad_clock && last_joypad_clock) begin
			joypad_bits <= {1'b0, joypad_bits[7:1]};
		end
		last_joypad_clock <= joypad_clock;
	end
end

assign joypad_out=famicom_latch;
assign joypad_clock=~famicom_pulse;
assign famicom_data=joypad_bits[0];

endmodule
