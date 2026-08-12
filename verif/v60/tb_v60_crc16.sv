//============================================================================
//  V60 CRC-16 directed test: byte-exact copy of OutRunners' boot ROM-check
//  inner routine (maincpu 0x1C98E-0x1C9BD).  The game computes a dual-lane
//  CRC (poly 0x8810, one register per 16-bit bus lane) with
//    xor.h [R10+], Rn ; shl.h R2(=-1), Rn ; bnl +5 ; xor.h R3(=0x8810), Rn
//  and enters its test mode when the result disagrees with the sums stored
//  in ROM.  This pins the negative-count shl.h carry/L-flag semantics and
//  dbr iteration count against a reference model of the same algorithm.
//============================================================================
`timescale 1ns/1ps

module tb_v60_crc16;

reg clk = 0, rst = 1;
always #10 clk = ~clk;

wire        c_req, c_we, c_ack;
wire [31:0] c_addr, c_wdata, c_rdata;
wire [1:0]  c_size;
wire        m_req, m_we, m_ack;
wire [23:1] m_addr;
wire [15:0] m_wdata, m_rdata;
wire [1:0]  m_be;

s32_v60 #(.START_PC(32'h0000_0000)) cpu (
    .clk(clk), .ce(1'b1), .rst(rst),
    .if_req(), .if_addr(), .if_data(64'd0), .if_ack(1'b0),
    .bus_req(c_req), .bus_we(c_we), .bus_addr(c_addr), .bus_size(c_size),
    .bus_wdata(c_wdata), .bus_rdata(c_rdata), .bus_ack(c_ack),
    .irq_n(1'b1), .irq_vector(8'h00), .irq_ack(),
    .nmi_n(1'b1),
    .dbg_pc(), .dbg_halted()
);

s32_v60_bus adapter (
    .clk(clk), .ce(1'b1), .rst(rst), .v70_mode(1'b0),
    .c_req(c_req), .c_we(c_we), .c_addr(c_addr), .c_size(c_size),
    .c_wdata(c_wdata), .c_rdata(c_rdata), .c_ack(c_ack),
    .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wdata(m_wdata),
    .m_be(m_be), .m_rdata(m_rdata), .m_ack(m_ack)
);

reg [15:0] ram [0:32767];
reg        ack_r;
assign m_rdata = ram[m_addr[15:1]];
assign m_ack   = ack_r;
always @(posedge clk) begin
    ack_r <= m_req & ~ack_r;
    if (m_req && m_we && !ack_r) begin
        if (m_be[0]) ram[m_addr[15:1]][7:0]  <= m_wdata[7:0];
        if (m_be[1]) ram[m_addr[15:1]][15:8] <= m_wdata[15:8];
    end
end

integer i, k;
reg [7:0] p [0:511];
initial begin
    for (i = 0; i < 32768; i = i + 1) ram[i] = 16'h0000;
    for (i = 0; i < 512; i = i + 1) p[i] = 8'h00;

    // driver at 0x0000
    k = 0;
    // MOVW #$100, R0        (length in bytes)
    p[k]=8'h2D; k++; p[k]=8'h20; k++; p[k]=8'hF4; k++;
    p[k]=8'h00; k++; p[k]=8'h01; k++; p[k]=8'h00; k++; p[k]=8'h00; k++;
    // MOVW #$1000, R10      (data base)
    p[k]=8'h2D; k++; p[k]=8'h2A; k++; p[k]=8'hF4; k++;
    p[k]=8'h00; k++; p[k]=8'h10; k++; p[k]=8'h00; k++; p[k]=8'h00; k++;
    // BSR $100  (disp16 from instruction start: 0x100 - 0x0E = 0xF2)
    p[k]=8'h48; k++; p[k]=8'hF2; k++; p[k]=8'h00; k++;
    // HALT
    p[k]=8'h00; k++;

    // game routine, byte-exact from orunners maincpu 0x1C98E, at 0x100
    k = 'h100;
    p[k]=8'h2D; k++; p[k]=8'h40; k++; p[k]=8'h69; k++;             // mov.w R0, R9
    p[k]=8'hAD; k++; p[k]=8'h29; k++; p[k]=8'hF4; k++; p[k]=8'hFE; k++; // shl.w #-2, R9
    p[k]=8'h1B; k++; p[k]=8'h20; k++; p[k]=8'hE1; k++;             // mov.h #1, R0
    p[k]=8'h1B; k++; p[k]=8'h21; k++; p[k]=8'hE1; k++;             // mov.h #1, R1
    p[k]=8'h39; k++; p[k]=8'h22; k++; p[k]=8'hE1; k++;             // neg.b #1, R2
    p[k]=8'h1B; k++; p[k]=8'h23; k++; p[k]=8'hF4; k++;             // mov.h #8810, R3
    p[k]=8'h10; k++; p[k]=8'h88; k++;
    p[k]=8'hB2; k++; p[k]=8'h60; k++; p[k]=8'h8A; k++;             // xor.h [R10+], R0
    p[k]=8'hAB; k++; p[k]=8'h42; k++; p[k]=8'h60; k++;             // shl.h R2, R0
    p[k]=8'h63; k++; p[k]=8'h05; k++;                              // bnl +5
    p[k]=8'hB2; k++; p[k]=8'h43; k++; p[k]=8'h60; k++;             // xor.h R3, R0
    p[k]=8'hB2; k++; p[k]=8'h61; k++; p[k]=8'h8A; k++;             // xor.h [R10+], R1
    p[k]=8'hAB; k++; p[k]=8'h42; k++; p[k]=8'h61; k++;             // shl.h R2, R1
    p[k]=8'h63; k++; p[k]=8'h05; k++;                              // bnl +5
    p[k]=8'hB2; k++; p[k]=8'h43; k++; p[k]=8'h61; k++;             // xor.h R3, R1
    p[k]=8'hC6; k++; p[k]=8'hA9; k++; p[k]=8'hEA; k++; p[k]=8'hFF; k++; // dbr R9, loop
    p[k]=8'hCA; k++;                                               // rsr

    for (i = 0; i < 256; i = i + 1)
        ram[i] = {p[2*i+1], p[2*i]};

    // data block at 0x1000: byte k = (k*7+3) & 0xFF
    for (i = 0; i < 128; i = i + 1) begin
        ram['h800 + i][7:0]  = (2*i)*7 + 3;
        ram['h800 + i][15:8] = (2*i+1)*7 + 3;
    end
end

// data-read size probe: log CPU-side bus requests into the data block
reg creq_d = 0;
always @(posedge clk) begin
    creq_d <= c_req;
    if (c_req && !creq_d && !c_we && c_addr >= 32'h1000 && c_addr < 32'h1100)
        $display("[bus] rd addr=%04x size=%0d", c_addr, c_size);
    if (c_ack && !c_we && c_addr >= 32'h1000 && c_addr < 32'h1100)
        $display("[bus] ack addr=%04x rdata=%08x ea_dim=%0d", c_addr, c_rdata,
            cpu.ea_dim);
end

// per-instruction trace of the first loop iterations
reg [31:0] tpc_d = 32'hffffffff;
integer tr_n = 0;
always @(posedge clk) begin
    if (cpu.dbg_pc != tpc_d) begin
        tpc_d <= cpu.dbg_pc;
        if (tr_n < 90 && cpu.dbg_pc >= 32'h110 && cpu.dbg_pc <= 32'h12f) begin
            tr_n = tr_n + 1;
            $display("[t] pc=%03x R0=%08x R1=%08x R2=%08x R9=%08x cy=%b",
                cpu.dbg_pc, cpu.r[0], cpu.r[1], cpu.r[2], cpu.r[9], cpu.f_cy);
        end
    end
end

initial begin
    repeat (8) @(posedge clk);
    rst = 0;
    repeat (40000) @(posedge clk);
    $display("R0=%08x R1=%08x R9=%08x R10=%08x halted=%0d",
        cpu.r[0], cpu.r[1], cpu.r[9], cpu.r[10], cpu.dbg_halted);
    // reference model of the identical algorithm: R0=38bb R1=13a5
    if (cpu.r[0][15:0] == 16'h38bb && cpu.r[1][15:0] == 16'h13a5 &&
        cpu.dbg_halted)
        $display("V60 CRC16 PASS");
    else
        $display("V60 CRC16 FAIL");
    $finish;
end

endmodule
