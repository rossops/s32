//============================================================================
//  V60 directed test: the OutRunners title-scene setup instruction forms.
//  Byte-exact encodings lifted from orunners maincpu:
//    10634: 2D 59 61        mov.w  R25, R1
//    10637: AD 21 F4 F0     shl.w  #-16, R1        (negative IMMEDIATE count)
//    1063B: A2 21 E1        and.h  #1, R1
//    19CD7: 44 73 C0 ..     movea.w disp[PC](R0), R19   (scaled PC index)
//    19D41: 1B 80 F4 72 00 B4 90 00   mov.h #72, [90[R20]]   (deferred store)
//    19D3C: 82 01 B4 8C 00  add.h  R1, [8C[R20]]   (deferred RMW)
//  The graphics bug hid in this sequence: the parity byte, the per-parity
//  pointer table entry, and the doubly-indirect target stores decide which
//  NBG layer pair member receives the scene scroll targets.
//============================================================================
`timescale 1ns/1ps

module tb_v60_dblind;

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

integer i, k, disp;
reg [7:0] p [0:511];
initial begin
    for (i = 0; i < 32768; i = i + 1) ram[i] = 16'h0000;
    for (i = 0; i < 512; i = i + 1) p[i] = 8'h00;

    k = 0;
    // MOVW #$00218000, R25
    p[k]=8'h2D; k++; p[k]=8'h39; k++; p[k]=8'hF4; k++;
    p[k]=8'h00; k++; p[k]=8'h80; k++; p[k]=8'h21; k++; p[k]=8'h00; k++;
    // mov.w R25, R1 ; shl.w #F0, R1 ; and.h #1, R1   (parity compute, =1)
    p[k]=8'h2D; k++; p[k]=8'h59; k++; p[k]=8'h61; k++;
    p[k]=8'hAD; k++; p[k]=8'h21; k++; p[k]=8'hF4; k++; p[k]=8'hF0; k++;
    p[k]=8'hA2; k++; p[k]=8'h21; k++; p[k]=8'hE1; k++;
    // mov.w R1, R9  (save parity for check)
    p[k]=8'h2D; k++; p[k]=8'h41; k++; p[k]=8'h69; k++;
    // MOVW #$400, R20
    p[k]=8'h2D; k++; p[k]=8'h34; k++; p[k]=8'hF4; k++;
    p[k]=8'h00; k++; p[k]=8'h04; k++; p[k]=8'h00; k++; p[k]=8'h00; k++;
    // movea.w 100[PC](R1), R19  (scaled PC-relative table: entry 1 -> +4)
    // encoding per 19CD7: 44 73 C1 F1 <disp16>  — index reg R1
    p[k]=8'h44; k++; p[k]=8'h73; k++; p[k]=8'hC1; k++; p[k]=8'hF1; k++;
    // disp16 from PC of instruction start to table at 0x180: filled below
    p[k]=8'h00; k++; p[k]=8'h00; k++;
    // mov.w [R19+], 90[R20]   (2D C0 93 34 90 00) — install pointer
    p[k]=8'h2D; k++; p[k]=8'hC0; k++; p[k]=8'h93; k++;
    p[k]=8'h34; k++; p[k]=8'h90; k++; p[k]=8'h00; k++;
    // mov.h #72, [90[R20]]    (1B 80 F4 72 00 B4 90 00) — deferred store
    p[k]=8'h1B; k++; p[k]=8'h80; k++; p[k]=8'hF4; k++;
    p[k]=8'h72; k++; p[k]=8'h00; k++;
    p[k]=8'hB4; k++; p[k]=8'h90; k++; p[k]=8'h00; k++;
    // MOVW #8, R1 then add.h R1, [90[R20]]  (82 01 B4 90 00) — deferred RMW
    p[k]=8'h2D; k++; p[k]=8'h21; k++; p[k]=8'hE8; k++;
    p[k]=8'h82; k++; p[k]=8'h01; k++; p[k]=8'hB4; k++;
    p[k]=8'h90; k++; p[k]=8'h00; k++;
    // br16 to phase 2 at 0x11B (7A <disp16 from instruction start>)
    disp = 'h11b - k;
    p[k]=8'h7A; p[k+1]=disp & 8'hff; p[k+2]=(disp>>8) & 8'hff; k=k+3;

    // ---- phase 2: byte-exact replica of the game's 0x19D1B-0x19D30 window,
    // placed so every instruction shares the game's low address bits.  The
    // stores execute right after an RSR return, PC = ...21, as on hardware.
    k = 'h11b;
    // jsr $1F0 (E8 F3 <abs32>) — game: jsr 179AC
    p[k]=8'hE8; k++; p[k]=8'hF3; k++; p[k]=8'hF0; k++;
    p[k]=8'h01; k++; p[k]=8'h00; k++; p[k]=8'h00; k++;
    // 0x121: mov.h #FFF0, [A0[R20]]
    p[k]=8'h1B; k++; p[k]=8'h80; k++; p[k]=8'hF4; k++;
    p[k]=8'hF0; k++; p[k]=8'hFF; k++;
    p[k]=8'hB4; k++; p[k]=8'hA0; k++; p[k]=8'h00; k++;
    // 0x129: mov.h #360, [8C[R20]]
    p[k]=8'h1B; k++; p[k]=8'h80; k++; p[k]=8'hF4; k++;
    p[k]=8'h60; k++; p[k]=8'h03; k++;
    p[k]=8'hB4; k++; p[k]=8'h8C; k++; p[k]=8'h00; k++;

    // ---- phase 3: MOVD quadword EA semantics (game 0x10734 / boot 0x7C9).
    // The scene wipe indexes by context id with mov.d, so the index must
    // scale by 8; the boot state-page clear steps [R10+] by 8.
    // MOVW #1, R0
    p[k]=8'h2D; k++; p[k]=8'h20; k++; p[k]=8'hE1; k++;
    // MOVW #$11112222, R1 ; MOVW #$33334444, R2 (MOVD pair R1:R2)
    p[k]=8'h2D; k++; p[k]=8'h21; k++; p[k]=8'hF4; k++;
    p[k]=8'h22; k++; p[k]=8'h22; k++; p[k]=8'h11; k++; p[k]=8'h11; k++;
    p[k]=8'h2D; k++; p[k]=8'h22; k++; p[k]=8'hF4; k++;
    p[k]=8'h44; k++; p[k]=8'h44; k++; p[k]=8'h33; k++; p[k]=8'h33; k++;
    // MOVW #$2000, R24
    p[k]=8'h2D; k++; p[k]=8'h38; k++; p[k]=8'hF4; k++;
    p[k]=8'h00; k++; p[k]=8'h20; k++; p[k]=8'h00; k++; p[k]=8'h00; k++;
    // mov.d R1, 290[R24](R0)   (3F 41 C0 38 90 02) — index 1 must scale x8
    p[k]=8'h3F; k++; p[k]=8'h41; k++; p[k]=8'hC0; k++;
    p[k]=8'h38; k++; p[k]=8'h90; k++; p[k]=8'h02; k++;
    // MOVW #$2400, R10 ; mov.d R1,[R10+] twice — step must be 8
    p[k]=8'h2D; k++; p[k]=8'h2A; k++; p[k]=8'hF4; k++;
    p[k]=8'h00; k++; p[k]=8'h24; k++; p[k]=8'h00; k++; p[k]=8'h00; k++;
    p[k]=8'h3F; k++; p[k]=8'h41; k++; p[k]=8'h8A; k++;
    p[k]=8'h3F; k++; p[k]=8'h41; k++; p[k]=8'h8A; k++;
    // HALT
    p[k]=8'h00; k++;
    // stub subroutine at 0x1F0: rsr
    p['h1f0]=8'hCA;

    // phase-2 pointers in the scene block: [R20+A0]=0x00031700,
    // [R20+8C]=0x00031800 (nonzero high words again) — written straight
    // into the RAM model (the p[] program image only spans 512 bytes)
    ram['h4a0>>1]=16'h1700; ram[('h4a0>>1)+1]=16'h0003;
    ram['h48c>>1]=16'h1800; ram[('h48c>>1)+1]=16'h0003;

    // patch the movea.w PC disp: instruction start = 0x17 + 7 + 3 = ... compute:
    // driver layout: movw(7) + parity(3+4+3) + save(3) + movw R20(7) = byte 27
    // movea.w at offset 27 (0x1B); disp16 points to 0x180 - 0x1B = 0x165
    p[27+4] = 8'h65; p[27+5] = 8'h01;

    // pointer table at 0x180: entry0 = 0x00011500, entry1 = 0x00021600.
    // Nonzero HIGH words matter: the game's pointers are 0x0020E296-style,
    // so a mov.w that copies only its low half forwards a pointer into ROM
    // space and the deferred store vanishes.
    p['h180]=8'h00; p['h181]=8'h15; p['h182]=8'h01; p['h183]=8'h00;
    p['h184]=8'h00; p['h185]=8'h16; p['h186]=8'h02; p['h187]=8'h00;

    for (i = 0; i < 256; i = i + 1)
        ram[i] = {p[2*i+1], p[2*i]};
end

integer errs;
initial begin
    errs = 0;
    repeat (8) @(posedge clk);
    rst = 0;
    repeat (30000) @(posedge clk);
    // parity: (0x218000 >> 16) & 1 = 1
    if (cpu.r[9][15:0] !== 16'h0001) begin
        errs = errs + 1;
        $display("FAIL parity: R9=%08x expected 1", cpu.r[9]);
    end
    // table entry 1 selected -> R19 = its EA (0x184) + 4 from the postinc
    if (cpu.r[19] !== 32'h0000_0188) begin
        errs = errs + 1;
        $display("FAIL table: R19=%08x expected 00000188", cpu.r[19]);
    end
    // full 32-bit pointer installed at 0x490 (high word must survive)
    if ({ram[('h490>>1)+1], ram['h490>>1]} !== 32'h0002_1600) begin
        errs = errs + 1;
        $display("FAIL ptr: [490]=%04x_%04x expected 0002_1600",
            ram[('h490>>1)+1], ram['h490>>1]);
    end
    // deferred store + RMW through 0x21600 (aliases to 0x1600 in this
    // 64 KiB model): mem = 0x72 + 8 = 0x7a
    if (ram['h1600>>1] !== 16'h007a) begin
        errs = errs + 1;
        $display("FAIL dblind: [1600]=%04x expected 007a", ram['h1600>>1]);
    end
    if (ram['h490>>1] == 16'h0072 || ram['h490>>1] == 16'h007a)
        $display("NOTE: store landed ON the pointer word, not through it");
    // phase 2 (post-RSR, game-aligned): stores must land at the pointer
    // targets 0x31700/0x31800 (RAM indices B80/C00), not at 2x the pointer
    if (ram['h1700>>1] !== 16'hfff0) begin
        errs = errs + 1;
        $display("FAIL p2-a0: [31700]=%04x expected fff0 (2x-ptr alias holds %04x)",
            ram['h1700>>1], ram[16'h1700]);
    end
    if (ram['h1800>>1] !== 16'h0360) begin
        errs = errs + 1;
        $display("FAIL p2-8c: [31800]=%04x expected 0360 (2x-ptr alias holds %04x)",
            ram['h1800>>1], ram[16'h1800]);
    end
    // phase 3: indexed MOVD with R0=1 must write 0x2000+0x290+1*8 = 0x2298
    if ({ram[('h2298>>1)+1], ram['h2298>>1]} !== 32'h1111_2222 ||
        {ram[('h229c>>1)+1], ram['h229c>>1]} !== 32'h3333_4444) begin
        errs = errs + 1;
        $display("FAIL movd-idx: [2298]=%04x %04x %04x %04x (x4-scale would hit 2294: %04x)",
            ram['h2298>>1], ram[('h2298>>1)+1],
            ram[('h229c>>1)], ram[('h229c>>1)+1], ram['h2294>>1]);
    end
    // phase 3: MOVD autoincrement steps by 8 — second qword at 0x2408
    if (ram['h2404>>1] !== 16'h4444 || ram['h2408>>1] !== 16'h2222 ||
        ram['h240c>>1] !== 16'h4444) begin
        errs = errs + 1;
        $display("FAIL movd-ai: [2404]=%04x [2408]=%04x [240c]=%04x (step-4 overlaps)",
            ram['h2404>>1], ram['h2408>>1], ram['h240c>>1]);
    end
    if (errs == 0) $display("V60 DBLIND PASS");
    else           $display("V60 DBLIND FAIL (%0d)", errs);
    $finish;
end

endmodule
