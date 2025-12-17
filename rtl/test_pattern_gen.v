//==============================================================================
// TEST PATTERN - Multi-Core Retro Computer System
//==============================================================================
// Autore: Angelo Arato
// Tesi: Architettura Ibrida FPGA/MCU per Ricreazione C64
// Sistemi emulati: Commodore 64, VIC-20, ZX Spectrum, Apple 1
//==============================================================================

module test_pattern_gen (
    input  wire       clk,      // 50MHz Clock
    input  wire       reset_n,
    input  wire       res_mode, // 0=640x480, 1=800x600
    output reg  [3:0] vga_r,
    output reg  [3:0] vga_g,
    output reg  [3:0] vga_b,
    output reg        vga_hsync,
    output reg        vga_vsync
);

//==============================================================================
// VGA TIMING - Dual Resolution Support
// res_mode=0: 640x480 @ 60Hz (25 MHz pixel clock)
// res_mode=1: 800x600 @ 72Hz (50 MHz pixel clock)
//==============================================================================

// Pixel clock divider per 640x480
reg pix_clk_div;
always @(posedge clk or negedge reset_n)
    if (!reset_n) pix_clk_div <= 0;
    else pix_clk_div <= ~pix_clk_div;

wire pix_clk_en = res_mode ? 1'b1 : pix_clk_div;

// Timing parameters
wire [10:0] H_VISIBLE = res_mode ? 11'd800  : 11'd640;
wire [10:0] H_FRONT   = res_mode ? 11'd56   : 11'd16;
wire [10:0] H_SYNC    = res_mode ? 11'd120  : 11'd96;
wire [10:0] H_TOTAL   = res_mode ? 11'd1040 : 11'd800;
wire [9:0]  V_VISIBLE = res_mode ? 10'd600  : 10'd480;
wire [9:0]  V_FRONT   = res_mode ? 10'd37   : 10'd10;
wire [9:0]  V_SYNC    = res_mode ? 10'd6    : 10'd2;
wire [9:0]  V_TOTAL   = res_mode ? 10'd666  : 10'd525;

reg [10:0] h_cnt;
reg [9:0] v_cnt;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        h_cnt <= 0; v_cnt <= 0;
    end else if (pix_clk_en) begin
        if (h_cnt == H_TOTAL-1) begin
            h_cnt <= 0;
            v_cnt <= (v_cnt == V_TOTAL-1) ? 0 : v_cnt + 1'd1;
        end else h_cnt <= h_cnt + 1'd1;
    end
end

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        vga_hsync <= 1; vga_vsync <= 1;
    end else begin
        vga_hsync <= ~((h_cnt >= H_VISIBLE+H_FRONT) && (h_cnt < H_VISIBLE+H_FRONT+H_SYNC));
        vga_vsync <= ~((v_cnt >= V_VISIBLE+V_FRONT) && (v_cnt < V_VISIBLE+V_FRONT+V_SYNC));
    end
end

wire visible = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);

//==============================================================================
// FUNZIONI GRAFICHE
//==============================================================================

// 1. Funzione "BIG" (Scala 2x) per Titoli e Loghi
// Disegna un carattere 8x8 in un'area 16x16
function draw_char_2x;
    input [9:0] tx, ty; // Coordinate schermo
    input [9:0] cx, cy; // Posizione carattere
    input [63:0] bmp;   // Bitmap
    reg [2:0] px, py;
    begin
        if (tx >= cx && tx < cx + 16 && ty >= cy && ty < cy + 16) begin
            px = (tx - cx) >> 1;
            py = (ty - cy) >> 1;
            draw_char_2x = bmp[(7-py)*8 + (7-px)];
        end else draw_char_2x = 0;
    end
endfunction

// 2. Funzione "SMALL" (Scala 1x) per la Firma
// Disegna un carattere 8x8 pixel-perfect (molto più definito)
function draw_char_1x;
    input [9:0] tx, ty;
    input [9:0] cx, cy;
    input [63:0] bmp;
    reg [2:0] px, py;
    begin
        if (tx >= cx && tx < cx + 8 && ty >= cy && ty < cy + 8) begin
            px = tx - cx;
            py = ty - cy;
            draw_char_1x = bmp[(7-py)*8 + (7-px)];
        end else draw_char_1x = 0;
    end
endfunction

//==============================================================================
// FONT BITMAPS (8x8)
//==============================================================================
// Alfabeto Maiuscolo
localparam C_A = 64'h3C66667E66666600; localparam C_B = 64'h7C66667C66667C00; localparam C_C = 64'h3C66606060663C00;
localparam C_D = 64'h786C6666666C7800; localparam C_E = 64'h7E60607C60607E00; localparam C_F = 64'h7E60607C60606000;
localparam C_G = 64'h3C66606E66663C00; localparam C_H = 64'h6666667E66666600; localparam C_I = 64'h3C18181818183C00;
localparam C_L = 64'h6060606060607E00; localparam C_M = 64'h667E5A4242424200; localparam C_N = 64'h6666767E6E666600;
localparam C_O = 64'h3C66666666663C00; localparam C_P = 64'h7C66667C60606000; 
// R Corretta: Gamba diagonale definita per non sembrare una P
localparam C_R = 64'h7C66667C786C6600; 
localparam C_S = 64'h3C60603C06063C00; localparam C_T = 64'h7E18181818181800; localparam C_U = 64'h6666666666663C00;
localparam C_V = 64'h66666666663C1800; localparam C_X = 64'h66663C183C666600; localparam C_Y = 64'h6666663C18181800;
localparam C_Z = 64'h7E060C1830607E00;

// Numeri e Simboli
localparam N_0 = 64'h3C66666666663C00; localparam N_1 = 64'h1838181818187E00; localparam N_2 = 64'h3C66061C30667E00;
localparam N_4 = 64'h0C1C2C4C7E0C0C00; localparam N_6 = 64'h3C60607C66663C00; 
localparam S_DOT = 64'h0000000000181800; localparam S_DASH = 64'h0000007E00000000;

// Alfabeto Minuscolo (per firma elegante)
localparam L_b = 64'h6060607C66667C00; localparam L_y = 64'h00006666663C180C; // y con coda
localparam L_r = 64'h0000566240404000; localparam L_a = 64'h00003C023E463A00;
localparam L_t = 64'h2020782020221C00; localparam L_o = 64'h00003C4242423C00;
localparam L_n = 64'h00005C6242424200; localparam L_g = 64'h00003E423C023C40; // g con coda
localparam L_e = 64'h00003C427E403C00; localparam L_l = 64'h6060606060603800;

//==============================================================================
// SFONDO - Griglia "Retro Tech"
//==============================================================================
wire grid_line = ((h_cnt % 40) == 0) || ((v_cnt % 40) == 0);
wire [3:0] bg_r = grid_line ? 4'h3 : 4'h1;
wire [3:0] bg_g = grid_line ? 4'h3 : 4'h1;
wire [3:0] bg_b = grid_line ? 4'h4 : 4'h2;

//==============================================================================
// TITOLO: "RETRO PC SYSTEM V1.0"
//==============================================================================
// Lunghezza: 20 car. Larghezza: 20*16 = 320px. 
// 800x600: StartX = (800-320)/2 = 240, Y = 30
// 640x480: StartX = (640-320)/2 = 160, Y = 20
wire [9:0] TIT_Y = res_mode ? 10'd30 : 10'd20;
wire [9:0] TIT_X = res_mode ? 10'd240 : 10'd160;
reg title_pix;
always @(*) begin
    title_pix = 0;
    if (v_cnt >= TIT_Y && v_cnt < TIT_Y+16) begin
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X + 0*16, TIT_Y, C_R);
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X + 1*16, TIT_Y, C_E);
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X + 2*16, TIT_Y, C_T);
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X + 3*16, TIT_Y, C_R);
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X + 4*16, TIT_Y, C_O);
        // Spazio
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X + 6*16, TIT_Y, C_P);
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X + 7*16, TIT_Y, C_C);
        // Spazio
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X + 9*16, TIT_Y, C_S);
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X +10*16, TIT_Y, C_Y);
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X +11*16, TIT_Y, C_S);
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X +12*16, TIT_Y, C_T);
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X +13*16, TIT_Y, C_E);
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X +14*16, TIT_Y, C_M);
        // Spazio
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X +16*16, TIT_Y, C_V);
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X +17*16, TIT_Y, N_1);
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X +18*16, TIT_Y, S_DOT);
        title_pix = title_pix | draw_char_2x(h_cnt, v_cnt, TIT_X +19*16, TIT_Y, N_0);
    end
end

//==============================================================================
// LAYOUT SISTEMI - dinamico per risoluzione
//==============================================================================
// Box: 180x100 per 640x480, 240x120 per 800x600
wire [8:0] BOX_W = res_mode ? 9'd240 : 9'd180;
wire [7:0] BOX_H = res_mode ? 8'd120 : 8'd100;
wire [7:0] GAP_Y = res_mode ? 8'd50  : 8'd30;
// Centrato verticalmente: (Vres - 2*BOX_H - GAP_Y) / 2
// 800x600: (600-120-50-120)/2 = 155
// 640x480: (480-100-30-100)/2 = 125
wire [8:0] START_Y = res_mode ? 9'd155 : 9'd125;
wire [8:0] BOX_GAP_X = res_mode ? 9'd80 : 9'd40;

// Calcolo posizioni box
// 800x600: colSx=(800-240*2-80)/2=120, colDx=440
// 640x480: colSx=(640-180*2-40)/2=120, colDx=340
wire [9:0] COL_LEFT  = res_mode ? 10'd120 : 10'd120;
wire [9:0] COL_RIGHT = res_mode ? 10'd440 : 10'd340;
wire [9:0] ROW1_TOP = START_Y;
wire [9:0] ROW2_TOP = START_Y + BOX_H + GAP_Y;

wire in_c64   = (h_cnt >= COL_LEFT)  && (h_cnt < COL_LEFT + BOX_W)  && (v_cnt >= ROW1_TOP) && (v_cnt < ROW1_TOP + BOX_H);
wire in_vic   = (h_cnt >= COL_RIGHT) && (h_cnt < COL_RIGHT + BOX_W) && (v_cnt >= ROW1_TOP) && (v_cnt < ROW1_TOP + BOX_H);
wire in_zx    = (h_cnt >= COL_LEFT)  && (h_cnt < COL_LEFT + BOX_W)  && (v_cnt >= ROW2_TOP) && (v_cnt < ROW2_TOP + BOX_H);
wire in_apple = (h_cnt >= COL_RIGHT) && (h_cnt < COL_RIGHT + BOX_W) && (v_cnt >= ROW2_TOP) && (v_cnt < ROW2_TOP + BOX_H);

// Coordinate relative nel box
wire [8:0] bx = (in_c64 || in_zx) ? (h_cnt - COL_LEFT) : (h_cnt - COL_RIGHT);
wire [7:0] by = (in_c64 || in_vic) ? (v_cnt - ROW1_TOP) : (v_cnt - ROW2_TOP);
wire box_border = (bx < 4 || bx >= BOX_W-4 || by < 4 || by >= BOX_H-4);

//==============================================================================
// GRAFICA SISTEMI - posizioni relative al centro del box
//==============================================================================

// Posizioni testo centrate nel box (relative a bx, by)
// Centro orizzontale box: BOX_W/2
// Centro verticale testo: BOX_H/2 - 8 (per char 16px)
wire [8:0] TEXT_CX = BOX_W >> 1;  // Centro X del box
wire [7:0] TEXT_CY = (BOX_H >> 1) - 8;  // Centro Y per testo

// --- C64 ---
reg c64_pix; reg c64_blue_logo; reg c64_red_logo;
always @(*) begin
    c64_pix = 0; c64_blue_logo = 0; c64_red_logo = 0;
    if (in_c64) begin
        // Logo C= centrato a sinistra del testo
        // Logo a circa 1/3 del box, testo a 2/3
        c64_blue_logo = (bx >= (TEXT_CX - 70) && bx < (TEXT_CX - 40) && by >= (TEXT_CY) && by < (TEXT_CY + 40)) && 
                        !((bx >= (TEXT_CX - 60) && bx < (TEXT_CX - 40) && by >= (TEXT_CY + 10) && by < (TEXT_CY + 30)));
        c64_red_logo  = (bx >= (TEXT_CX - 50) && bx < (TEXT_CX - 20) && ((by >= (TEXT_CY + 12) && by < (TEXT_CY + 18)) || (by >= (TEXT_CY + 22) && by < (TEXT_CY + 28))));
        // Testo "C64" centrato
        c64_pix = c64_pix | draw_char_2x(bx, by, TEXT_CX - 10, TEXT_CY + 12, C_C);
        c64_pix = c64_pix | draw_char_2x(bx, by, TEXT_CX + 6, TEXT_CY + 12, N_6);
        c64_pix = c64_pix | draw_char_2x(bx, by, TEXT_CX + 22, TEXT_CY + 12, N_4);
    end
end

// --- VIC-20 ---
reg vic_pix;
always @(*) begin
    vic_pix = 0;
    if (in_vic) begin
        // "VIC-20" centrato (6 chars * 16 = 96px, offset = -48)
        vic_pix = vic_pix | draw_char_2x(bx, by, TEXT_CX - 48, TEXT_CY + 10, C_V);
        vic_pix = vic_pix | draw_char_2x(bx, by, TEXT_CX - 32, TEXT_CY + 10, C_I);
        vic_pix = vic_pix | draw_char_2x(bx, by, TEXT_CX - 16, TEXT_CY + 10, C_C);
        vic_pix = vic_pix | draw_char_2x(bx, by, TEXT_CX, TEXT_CY + 10, S_DASH);
        vic_pix = vic_pix | draw_char_2x(bx, by, TEXT_CX + 16, TEXT_CY + 10, N_2);
        vic_pix = vic_pix | draw_char_2x(bx, by, TEXT_CX + 32, TEXT_CY + 10, N_0);
    end
end

// --- ZX SPECTRUM ---
reg zx_pix;
always @(*) begin
    zx_pix = 0;
    if (in_zx) begin
        // "ZX" centrato (2 chars * 16 = 32px, offset = -16)
        zx_pix = zx_pix | draw_char_2x(bx, by, TEXT_CX - 20, TEXT_CY + 10, C_Z);
        zx_pix = zx_pix | draw_char_2x(bx, by, TEXT_CX + 4, TEXT_CY + 10, C_X);
    end
end
wire zx_stripe = (bx + by > (BOX_W/2 + BOX_H/2));
wire [1:0] zx_col_idx = (bx + by - (BOX_W/2 + BOX_H/2)) / 10; 

// --- APPLE 1 ---
reg blink; reg [5:0] bcnt;
always @(posedge clk) if (v_cnt==0 && h_cnt==0) begin bcnt<=bcnt+1; blink<=bcnt[5]; end

reg apple_pix;
always @(*) begin
    apple_pix = 0;
    if (in_apple) begin
        // "APPLE 1" centrato (7 chars * 16 = 112px, offset = -56)
        apple_pix = apple_pix | draw_char_2x(bx, by, TEXT_CX - 56, TEXT_CY + 10, C_A);
        apple_pix = apple_pix | draw_char_2x(bx, by, TEXT_CX - 40, TEXT_CY + 10, C_P);
        apple_pix = apple_pix | draw_char_2x(bx, by, TEXT_CX - 24, TEXT_CY + 10, C_P);
        apple_pix = apple_pix | draw_char_2x(bx, by, TEXT_CX - 8, TEXT_CY + 10, C_L);
        apple_pix = apple_pix | draw_char_2x(bx, by, TEXT_CX + 8, TEXT_CY + 10, C_E);
        // Spazio
        apple_pix = apple_pix | draw_char_2x(bx, by, TEXT_CX + 40, TEXT_CY + 10, N_1);
    end
end
// Cursore dopo l'1
wire apple_cursor = blink && in_apple && (bx >= TEXT_CX + 56 && bx < TEXT_CX + 72 && by >= TEXT_CY + 10 && by < TEXT_CY + 26);

//==============================================================================
// FIRMA: "by Arato Angelo" (HIGH RESOLUTION 1x)
//==============================================================================
// Testo 15 chars * 8 px = 120 px width. 
// 800x600: Centered (800-120)/2 = 340, Y = 560
// 640x480: Centered (640-120)/2 = 260, Y = 450
wire [9:0] SIGN_X = res_mode ? 10'd340 : 10'd260; 
wire [9:0] SIGN_Y = res_mode ? 10'd560 : 10'd450;
reg sign_pix;
wire [9:0] sx = h_cnt; wire [9:0] sy = v_cnt;
always @(*) begin
    sign_pix = 0;
    if (v_cnt >= SIGN_Y && v_cnt < SIGN_Y+8) begin // Altezza 8 pixel (1x)
        // "by "
        sign_pix = sign_pix | draw_char_1x(sx, sy, SIGN_X+0*8, SIGN_Y, L_b);
        sign_pix = sign_pix | draw_char_1x(sx, sy, SIGN_X+1*8, SIGN_Y, L_y);
        // "Arato "
        sign_pix = sign_pix | draw_char_1x(sx, sy, SIGN_X+3*8, SIGN_Y, C_A);
        sign_pix = sign_pix | draw_char_1x(sx, sy, SIGN_X+4*8, SIGN_Y, L_r);
        sign_pix = sign_pix | draw_char_1x(sx, sy, SIGN_X+5*8, SIGN_Y, L_a);
        sign_pix = sign_pix | draw_char_1x(sx, sy, SIGN_X+6*8, SIGN_Y, L_t);
        sign_pix = sign_pix | draw_char_1x(sx, sy, SIGN_X+7*8, SIGN_Y, L_o);
        // "Angelo"
        sign_pix = sign_pix | draw_char_1x(sx, sy, SIGN_X+9*8, SIGN_Y, C_A);
        sign_pix = sign_pix | draw_char_1x(sx, sy, SIGN_X+10*8, SIGN_Y, L_n);
        sign_pix = sign_pix | draw_char_1x(sx, sy, SIGN_X+11*8, SIGN_Y, L_g);
        sign_pix = sign_pix | draw_char_1x(sx, sy, SIGN_X+12*8, SIGN_Y, L_e);
        sign_pix = sign_pix | draw_char_1x(sx, sy, SIGN_X+13*8, SIGN_Y, L_l);
        sign_pix = sign_pix | draw_char_1x(sx, sy, SIGN_X+14*8, SIGN_Y, L_o);
    end
end

//==============================================================================
// OUTPUT MIXER
//==============================================================================
always @(*) begin
    if (!visible) begin
        vga_r = 0; vga_g = 0; vga_b = 0;
    end else begin
        // Background
        vga_r = bg_r; vga_g = bg_g; vga_b = bg_b;

        // Titolo (Giallo)
        if (title_pix) begin vga_r=15; vga_g=15; vga_b=2; end

        // --- C64 (Blu) ---
        if (in_c64) begin
            if (box_border) begin vga_r=8; vga_g=8; vga_b=15; end // Light Blue
            else if (c64_red_logo) begin vga_r=12; vga_g=2; vga_b=2; end // Red =
            else if (c64_blue_logo) begin vga_r=6; vga_g=4; vga_b=14; end // Blue C
            else if (c64_pix) begin vga_r=8; vga_g=8; vga_b=15; end // Text
            else begin vga_r=4; vga_g=4; vga_b=10; end // BG
        end
        
        // --- VIC-20 (Bianco/Ciano) ---
        else if (in_vic) begin
            if (box_border) begin vga_r=0; vga_g=15; vga_b=15; end // Cyan
            else if (vic_pix) begin vga_r=0; vga_g=0; vga_b=12; end // Blue Text
            else begin vga_r=15; vga_g=15; vga_b=15; end // White BG
        end

        // --- ZX Spectrum (Grigio/Rainbow) ---
        else if (in_zx) begin
            if (box_border) begin vga_r=8; vga_g=8; vga_b=8; end // Gray
            else if (zx_pix) begin vga_r=0; vga_g=0; vga_b=0; end // Black Text (priorità!)
            else if (zx_stripe) begin
                // Sequenza Originale: Rosso, Giallo, Verde, Turchese
                case(zx_col_idx[1:0])
                    0: begin vga_r=14; vga_g=0; vga_b=0; end  // Rosso
                    1: begin vga_r=14; vga_g=14; vga_b=0; end // Giallo
                    2: begin vga_r=0; vga_g=14; vga_b=0; end  // Verde
                    3: begin vga_r=0; vga_g=14; vga_b=14; end // Turchese
                endcase
            end
            else begin vga_r=12; vga_g=12; vga_b=12; end // Light Gray BG
        end

        // --- Apple 1 (Nero/Verde) ---
        else if (in_apple) begin
            if (box_border) begin vga_r=6; vga_g=6; vga_b=6; end // Dark Gray
            else if (apple_pix || apple_cursor) begin vga_r=0; vga_g=15; vga_b=0; end // Green
            else begin vga_r=0; vga_g=0; vga_b=0; end // Black
        end

        // Firma (Grigio/Bianco, molto definita)
        if (sign_pix) begin vga_r=13; vga_g=13; vga_b=13; end
    end
end

endmodule