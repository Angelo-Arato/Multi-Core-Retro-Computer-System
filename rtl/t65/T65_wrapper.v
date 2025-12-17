//==============================================================================
// T65 Wrapper - Interfaccia Verilog per CPU T65 VHDL
//==============================================================================
// Questo modulo wrappa la CPU T65 VHDL per uso in progetti Verilog
//==============================================================================

module T65_wrapper (
    input  wire        clk,
    input  wire        enable,
    input  wire        reset_n,
    
    output wire [15:0] addr,
    input  wire [7:0]  data_in,
    output wire [7:0]  data_out,
    output wire        we,
    
    input  wire        irq_n,
    input  wire        nmi_n,
    input  wire        rdy,
    
    output wire        sync        // Opcode fetch indicator
);

wire [23:0] addr_full;
wire        r_w_n;
wire        sync_int;

assign addr = addr_full[15:0];
assign we = ~r_w_n;
assign sync = sync_int;

T65 cpu (
    .Mode(2'b00),        // 6502 mode
    .BCD_en(1'b1),       // BCD enabled
    .Res_n(reset_n),
    .Enable(enable),
    .Clk(clk),
    .Rdy(rdy),
    .Abort_n(1'b1),
    .IRQ_n(irq_n),
    .NMI_n(nmi_n),
    .SO_n(1'b1),
    .R_W_n(r_w_n),
    .Sync(sync_int),
    .EF(),
    .MF(),
    .XF(),
    .ML_n(),
    .VP_n(),
    .VDA(),
    .VPA(),
    .A(addr_full),
    .DI(data_in),
    .DO(data_out),
    .Regs(),
    .DEBUG(),
    .NMI_ack()
);

endmodule
