//==============================================================================
// T80 Wrapper - Interfaccia Verilog per CPU Z80 VHDL
//==============================================================================
// Wrapper per il core T80a Z80 (versione con interfaccia standard)
// Modalità: 0=Z80, 1=Fast Z80, 2=8080, 3=GameBoy
//==============================================================================

module T80_wrapper (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        enable,
    
    // Bus
    output wire [15:0] addr,
    input  wire [7:0]  data_in,
    output wire [7:0]  data_out,
    output wire        we,
    output wire        rd,
    
    // I/O
    output wire        iorq,
    output wire        mreq,
    output wire        m1_n,
    
    // Interrupts
    input  wire        int_n,
    input  wire        nmi_n,
    input  wire        wait_n,
    
    // Status
    output wire        halt_n,
    output wire        rfsh_n
);

// Segnali interni (active low dal T80a)
wire mreq_n_internal;
wire iorq_n_internal;
wire rd_n_internal;
wire wr_n_internal;

// Converti da active-low a active-high per logica positiva
assign we = ~wr_n_internal;
assign rd = ~rd_n_internal;
assign iorq = ~iorq_n_internal;
assign mreq = ~mreq_n_internal;

T80a #(
    .Mode(0)       // Z80 mode
) cpu (
    .RESET_n(reset_n),
    .CLK_n(clk),
    .CEN(enable),
    .WAIT_n(wait_n),
    .INT_n(int_n),
    .NMI_n(nmi_n),
    .BUSRQ_n(1'b1),
    .M1_n(m1_n),
    .MREQ_n(mreq_n_internal),
    .IORQ_n(iorq_n_internal),
    .RD_n(rd_n_internal),
    .WR_n(wr_n_internal),
    .RFSH_n(rfsh_n),
    .HALT_n(halt_n),
    .BUSAK_n(),
    .A(addr),
    .Din(data_in),
    .Dout(data_out),
    .Den(),
    // Debug outputs (non usati)
    .TS(),
    .Regs(),
    .PdcData()
);

endmodule
