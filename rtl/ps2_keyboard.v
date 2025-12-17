//==============================================================================
// PS/2 KEYBOARD INTERFACE - Layout Italiano
// Converts PS/2 scancodes to ASCII with key_code + key_strobe output
// Supporta frecce direzionali e layout italiano
//==============================================================================

module ps2_keyboard (
    input  wire        clk,           // System clock (50MHz)
    input  wire        reset_n,       // Active low reset
    
    // PS/2 interface
    input  wire        ps2_clk,
    input  wire        ps2_data,
    
    // Output to computer core
    output reg  [7:0]  key_code,
    output reg         key_strobe,
    
    // Modifiers
    output reg         key_shift,
    output reg         key_ctrl,
    output reg         key_caps
);

//==============================================================================
// PS/2 CLOCK SYNCHRONIZATION
//==============================================================================
reg [2:0] ps2_clk_sync;
reg [2:0] ps2_data_sync;

always @(posedge clk) begin
    ps2_clk_sync  <= {ps2_clk_sync[1:0], ps2_clk};
    ps2_data_sync <= {ps2_data_sync[1:0], ps2_data};
end

wire ps2_clk_fall = ps2_clk_sync[2] && !ps2_clk_sync[1];
wire ps2_data_in  = ps2_data_sync[1];

//==============================================================================
// PS/2 SERIAL RECEIVER
//==============================================================================
reg [3:0]  bit_count;
reg [10:0] shift_reg;
reg        rx_done;
reg [7:0]  scancode;
reg [15:0] rx_timeout;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        bit_count  <= 4'd0;
        shift_reg  <= 11'd0;
        rx_done    <= 1'b0;
        scancode   <= 8'd0;
        rx_timeout <= 16'd0;
    end
    else begin
        rx_done <= 1'b0;
        
        if (rx_timeout == 16'd65535) begin
            bit_count <= 4'd0;
            rx_timeout <= 16'd0;
        end
        else if (bit_count != 4'd0) begin
            rx_timeout <= rx_timeout + 16'd1;
        end
        
        if (ps2_clk_fall) begin
            rx_timeout <= 16'd0;
            shift_reg <= {ps2_data_in, shift_reg[10:1]};
            
            if (bit_count == 4'd10) begin
                bit_count <= 4'd0;
                scancode  <= shift_reg[9:2];
                rx_done   <= 1'b1;
            end
            else begin
                bit_count <= bit_count + 4'd1;
            end
        end
    end
end

//==============================================================================
// SCANCODE PROCESSOR
//==============================================================================
reg key_release;
reg extended;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        key_release <= 1'b0;
        extended    <= 1'b0;
        key_shift   <= 1'b0;
        key_ctrl    <= 1'b0;
        key_caps    <= 1'b0;
        key_code    <= 8'd0;
        key_strobe  <= 1'b0;
    end
    else begin
        key_strobe <= 1'b0;
        
        if (rx_done) begin
            if (scancode == 8'hF0) begin
                key_release <= 1'b1;
            end
            else if (scancode == 8'hE0) begin
                extended <= 1'b1;
            end
            else begin
                if (key_release) begin
                    key_release <= 1'b0;
                    extended    <= 1'b0;
                    case (scancode)
                        8'h12, 8'h59: key_shift <= 1'b0;
                        8'h14:        key_ctrl  <= 1'b0;
                        default: ;
                    endcase
                end
                else begin
                    // Key pressed
                    case (scancode)
                        8'h12, 8'h59: begin
                            key_shift <= 1'b1;
                            extended <= 1'b0;
                        end
                        8'h14: begin
                            key_ctrl <= 1'b1;
                            extended <= 1'b0;
                        end
                        8'h58: begin
                            key_caps <= ~key_caps;
                            extended <= 1'b0;
                        end
                        default: begin
                            if (extended) begin
                                // Extended keys - arrows
                                case (scancode)
                                    8'h75: begin key_code <= 8'h91; key_strobe <= 1'b1; end  // Up (C64 cursor up)
                                    8'h72: begin key_code <= 8'h11; key_strobe <= 1'b1; end  // Down (cursor down)
                                    8'h6B: begin key_code <= 8'h9D; key_strobe <= 1'b1; end  // Left (C64 cursor left)
                                    8'h74: begin key_code <= 8'h1D; key_strobe <= 1'b1; end  // Right (cursor right)
                                    8'h71: begin key_code <= 8'h7F; key_strobe <= 1'b1; end  // Delete
                                    8'h70: begin key_code <= 8'h94; key_strobe <= 1'b1; end  // Insert
                                    8'h6C: begin key_code <= 8'h13; key_strobe <= 1'b1; end  // Home (C64 home)
                                    8'h69: begin key_code <= 8'h04; key_strobe <= 1'b1; end  // End
                                    8'h4A: begin key_code <= 8'h2F; key_strobe <= 1'b1; end  // Numpad /
                                    8'h5A: begin key_code <= 8'h0D; key_strobe <= 1'b1; end  // Numpad Enter
                                    default: ;
                                endcase
                                extended <= 1'b0;
                            end
                            else begin
                                // Normal keys
                                key_code <= convert_it(scancode, key_shift, key_caps, key_ctrl);
                                if (convert_it(scancode, key_shift, key_caps, key_ctrl) != 8'd0)
                                    key_strobe <= 1'b1;
                            end
                        end
                    endcase
                    if (!extended) extended <= 1'b0;
                end
            end
        end
    end
end

//==============================================================================
// SCANCODE TO ASCII - Italian Layout
//==============================================================================
function [7:0] convert_it;
    input [7:0] sc;
    input shift;
    input caps;
    input ctrl;
    reg use_upper;
    begin
        use_upper = shift ^ caps;
        convert_it = 8'd0;
        
        if (ctrl) begin
            case (sc)
                8'h1C: convert_it = 8'h01;  // Ctrl+A
                8'h32: convert_it = 8'h02;  // Ctrl+B
                8'h21: convert_it = 8'h03;  // Ctrl+C
                8'h23: convert_it = 8'h04;  // Ctrl+D
                8'h24: convert_it = 8'h05;  // Ctrl+E
                8'h2B: convert_it = 8'h06;  // Ctrl+F
                8'h34: convert_it = 8'h07;  // Ctrl+G
                8'h33: convert_it = 8'h08;  // Ctrl+H (BS)
                8'h43: convert_it = 8'h09;  // Ctrl+I (TAB)
                8'h3B: convert_it = 8'h0A;  // Ctrl+J (LF)
                8'h42: convert_it = 8'h0B;  // Ctrl+K
                8'h4B: convert_it = 8'h0C;  // Ctrl+L
                8'h3A: convert_it = 8'h0D;  // Ctrl+M (CR)
                8'h31: convert_it = 8'h0E;  // Ctrl+N
                8'h44: convert_it = 8'h0F;  // Ctrl+O
                8'h4D: convert_it = 8'h10;  // Ctrl+P
                8'h15: convert_it = 8'h11;  // Ctrl+Q
                8'h2D: convert_it = 8'h12;  // Ctrl+R
                8'h1B: convert_it = 8'h13;  // Ctrl+S
                8'h2C: convert_it = 8'h14;  // Ctrl+T
                8'h3C: convert_it = 8'h15;  // Ctrl+U
                8'h2A: convert_it = 8'h16;  // Ctrl+V
                8'h1D: convert_it = 8'h17;  // Ctrl+W
                8'h22: convert_it = 8'h18;  // Ctrl+X
                8'h35: convert_it = 8'h19;  // Ctrl+Y
                8'h1A: convert_it = 8'h1A;  // Ctrl+Z
                default: convert_it = 8'd0;
            endcase
        end
        else begin
            case (sc)
                // Letters
                8'h1C: convert_it = use_upper ? 8'h41 : 8'h61;  // A
                8'h32: convert_it = use_upper ? 8'h42 : 8'h62;  // B
                8'h21: convert_it = use_upper ? 8'h43 : 8'h63;  // C
                8'h23: convert_it = use_upper ? 8'h44 : 8'h64;  // D
                8'h24: convert_it = use_upper ? 8'h45 : 8'h65;  // E
                8'h2B: convert_it = use_upper ? 8'h46 : 8'h66;  // F
                8'h34: convert_it = use_upper ? 8'h47 : 8'h67;  // G
                8'h33: convert_it = use_upper ? 8'h48 : 8'h68;  // H
                8'h43: convert_it = use_upper ? 8'h49 : 8'h69;  // I
                8'h3B: convert_it = use_upper ? 8'h4A : 8'h6A;  // J
                8'h42: convert_it = use_upper ? 8'h4B : 8'h6B;  // K
                8'h4B: convert_it = use_upper ? 8'h4C : 8'h6C;  // L
                8'h3A: convert_it = use_upper ? 8'h4D : 8'h6D;  // M
                8'h31: convert_it = use_upper ? 8'h4E : 8'h6E;  // N
                8'h44: convert_it = use_upper ? 8'h4F : 8'h6F;  // O
                8'h4D: convert_it = use_upper ? 8'h50 : 8'h70;  // P
                8'h15: convert_it = use_upper ? 8'h51 : 8'h71;  // Q
                8'h2D: convert_it = use_upper ? 8'h52 : 8'h72;  // R
                8'h1B: convert_it = use_upper ? 8'h53 : 8'h73;  // S
                8'h2C: convert_it = use_upper ? 8'h54 : 8'h74;  // T
                8'h3C: convert_it = use_upper ? 8'h55 : 8'h75;  // U
                8'h2A: convert_it = use_upper ? 8'h56 : 8'h76;  // V
                8'h1D: convert_it = use_upper ? 8'h57 : 8'h77;  // W
                8'h22: convert_it = use_upper ? 8'h58 : 8'h78;  // X
                8'h35: convert_it = use_upper ? 8'h59 : 8'h79;  // Y
                8'h1A: convert_it = use_upper ? 8'h5A : 8'h7A;  // Z
                
                // Numbers - Italian layout (Shift = symbol above)
                8'h45: convert_it = shift ? 8'h3D : 8'h30;  // = 0
                8'h16: convert_it = shift ? 8'h21 : 8'h31;  // ! 1
                8'h1E: convert_it = shift ? 8'h22 : 8'h32;  // " 2
                8'h26: convert_it = shift ? 8'h9C : 8'h33;  // £ 3
                8'h25: convert_it = shift ? 8'h24 : 8'h34;  // $ 4
                8'h2E: convert_it = shift ? 8'h25 : 8'h35;  // % 5
                8'h36: convert_it = shift ? 8'h26 : 8'h36;  // & 6
                8'h3D: convert_it = shift ? 8'h2F : 8'h37;  // / 7
                8'h3E: convert_it = shift ? 8'h28 : 8'h38;  // ( 8
                8'h46: convert_it = shift ? 8'h29 : 8'h39;  // ) 9
                
                // Special
                8'h5A: convert_it = 8'h0D;  // Enter
                8'h29: convert_it = 8'h20;  // Space
                8'h66: convert_it = 8'h08;  // Backspace
                8'h0D: convert_it = 8'h09;  // Tab
                8'h76: convert_it = 8'h1B;  // ESC
                
                // Italian punctuation - row by row
                // Top row after 0: ' ì
                8'h4E: convert_it = shift ? 8'h3F : 8'h27;  // ? '
                8'h55: convert_it = shift ? 8'h5E : 8'h69;  // ^ ì -> i
                
                // Row with + and keys near Enter
                8'h54: convert_it = shift ? 8'h2A : 8'h2B;  // * +
                8'h5B: convert_it = shift ? 8'h5D : 8'h5B;  // ] [
                8'h5D: convert_it = shift ? 8'h40 : 8'h23;  // @ # (ù key)
                
                // Row with ò à 
                8'h4C: convert_it = shift ? 8'h43 : 8'h3B;  // ç ; -> C ;
                8'h52: convert_it = shift ? 8'hB0 : 8'h60;  // ° ` (à key)
                
                // Bottom row - comma period minus
                8'h41: convert_it = shift ? 8'h3B : 8'h2C;  // ; ,
                8'h49: convert_it = shift ? 8'h3A : 8'h2E;  // : .
                8'h4A: convert_it = shift ? 8'h5F : 8'h2D;  // _ -
                
                // Key near Z (< >)
                8'h61: convert_it = shift ? 8'h3E : 8'h3C;  // > <
                
                // Backslash key (between left shift and Z on some keyboards)
                8'h0E: convert_it = shift ? 8'h7C : 8'h5C;  // | \
                
                // Numpad
                8'h70: convert_it = 8'h30;  // 0
                8'h69: convert_it = 8'h31;  // 1
                8'h72: convert_it = 8'h32;  // 2
                8'h7A: convert_it = 8'h33;  // 3
                8'h6B: convert_it = 8'h34;  // 4
                8'h73: convert_it = 8'h35;  // 5
                8'h74: convert_it = 8'h36;  // 6
                8'h6C: convert_it = 8'h37;  // 7
                8'h75: convert_it = 8'h38;  // 8
                8'h7D: convert_it = 8'h39;  // 9
                8'h79: convert_it = 8'h2B;  // +
                8'h7B: convert_it = 8'h2D;  // -
                8'h7C: convert_it = 8'h2A;  // *
                8'h71: convert_it = 8'h2E;  // .
                
                // Function keys F1-F12 -> codes 0x85-0x90
                8'h05: convert_it = 8'h85;  // F1
                8'h06: convert_it = 8'h86;  // F2
                8'h04: convert_it = 8'h87;  // F3
                8'h0C: convert_it = 8'h88;  // F4
                8'h03: convert_it = 8'h89;  // F5
                8'h0B: convert_it = 8'h8A;  // F6
                8'h83: convert_it = 8'h8B;  // F7
                8'h0A: convert_it = 8'h8C;  // F8
                8'h01: convert_it = 8'h8D;  // F9
                8'h09: convert_it = 8'h8E;  // F10
                8'h78: convert_it = 8'h8F;  // F11
                8'h07: convert_it = 8'h90;  // F12
                
                default: convert_it = 8'd0;
            endcase
        end
    end
endfunction

endmodule
