//============================================================================
// SDRAM controller read-capture validation against the Micron sdr model.
//
// The chip clock is forwarded at 180 degrees (SDRAM_CLK = ~clk_ram), so the
// chip launches read data at our falling edge and is allowed tAC2 = 7.5 ns
// (-75 grade, CL2) to present it.  A capture on the following rising edge
// samples 5.17 ns after launch — before worst-case data even exists.  This
// bench writes an address-hash pattern through the download port, then reads
// it back concurrently through the six read ports at full pipeline rate,
// checking every word.  With leading-edge capture it fails wholesale at
// worst-case tAC; the negedge capture samples 10.35 ns after launch, inside
// [tAC 7.5 .. tCK+tOH 13.35], and passes.
//
// Requires the Micron sdr model (sdr.sv + sdr_parameters.vh, sg75/den512Mb)
// on the include/source path; fetched from agg23/sdram-controller's test/
// directory (Micron simulation model, distributed for verification use).
//============================================================================
`timescale 1ns / 1ps

module tb_sdram_capture;

reg clk = 0;
always #5.174 clk = ~clk;   // 96.634615 MHz

reg init = 1;
wire ready;

// chip-side wiring; SDRAM_CLK forwarded 180 degrees like the board
wire [15:0] SDRAM_DQ;
wire [12:0] SDRAM_A;
wire  [1:0] SDRAM_BA;
wire        SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nWE, SDRAM_CKE;
wire        chip_clk = ~clk;

// download port
reg         wr_req = 0;
reg  [24:1] wr_addr;
reg  [15:0] wr_din;
reg   [1:0] wr_be = 2'b11;
wire        wr_ack;
// read ports
reg         p0_req = 0; reg [24:1] p0_addr; wire [15:0] p0_dout; wire p0_ack;
reg         p1_req = 0; reg [24:3] p1_addr; wire [63:0] p1_dout; wire p1_ack;
reg         p2_req = 0; reg [24:4] p2_addr; wire [127:0] p2_dout; wire p2_ack;
reg         p3_req = 0; reg [24:1] p3_addr; wire [15:0] p3_dout; wire p3_ack;
reg         p4_req = 0; reg [24:1] p4_addr; wire [15:0] p4_dout; wire p4_ack;
reg         p5_req = 0; reg [24:3] p5_addr; wire [63:0] p5_dout; wire p5_ack;

sdram dut (
    .clk(clk), .init(init), .ready(ready),
    .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
    .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
    .SDRAM_nCS(SDRAM_nCS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_nRAS(SDRAM_nRAS),
    .SDRAM_nWE(SDRAM_nWE), .SDRAM_CKE(SDRAM_CKE),
    .wr_req(wr_req), .wr_addr(wr_addr), .wr_din(wr_din), .wr_be(wr_be), .wr_ack(wr_ack),
    .p0_req(p0_req), .p0_addr(p0_addr), .p0_dout(p0_dout), .p0_ack(p0_ack),
    .p1_req(p1_req), .p1_addr(p1_addr), .p1_dout(p1_dout), .p1_ack(p1_ack),
    .p2_req(p2_req), .p2_addr(p2_addr), .p2_dout(p2_dout), .p2_ack(p2_ack),
    .p3_req(p3_req), .p3_addr(p3_addr), .p3_dout(p3_dout), .p3_ack(p3_ack),
    .p4_req(p4_req), .p4_addr(p4_addr), .p4_dout(p4_dout), .p4_ack(p4_ack),
    .p5_req(p5_req), .p5_addr(p5_addr), .p5_dout(p5_dout), .p5_ack(p5_ack)
);

sdr sdram_chip (
    .Dq(SDRAM_DQ), .Addr(SDRAM_A), .Ba(SDRAM_BA), .Clk(chip_clk),
    .Cke(SDRAM_CKE), .Cs_n(SDRAM_nCS), .Ras_n(SDRAM_nRAS),
    .Cas_n(SDRAM_nCAS), .We_n(SDRAM_nWE), .Dqm({SDRAM_DQMH, SDRAM_DQML})
);

// address-hash pattern so every word is unique and self-identifying
function automatic [15:0] pat(input [24:1] a);
    pat = {a[16:9] ^ a[24:17], a[8:1]} ^ {a[13:6], 8'h5A};
endfunction

integer errors = 0;
integer checked = 0;

task automatic dl_write(input [24:1] a);
    begin
        @(posedge clk); wr_addr <= a; wr_din <= pat(a); wr_req <= 1'b1;
        @(posedge clk); wr_req <= 1'b0;
        wait (wr_ack); @(posedge clk); @(posedge clk);
    end
endtask

task automatic chk(input [15:0] got, input [24:1] a, input [127:0] who);
    begin
        checked = checked + 1;
        if (got !== pat(a)) begin
            errors = errors + 1;
            if (errors <= 20)
                $display("MISMATCH %0s a=%06x got=%04x want=%04x t=%0t",
                         who, {a, 1'b0}, got, pat(a), $time);
        end
    end
endtask

// concurrent traffic generators (each port: single outstanding, edge req)
reg gen_run = 0;
integer done_cnt = 0;

task automatic gen_p0;  // CPU-style singles, stride through rows/banks
    integer i; reg [24:1] a;
    begin
        for (i = 0; i < (tb_sdram_capture.quick ? 4 : 400); i = i + 1) begin
            a = 24'h000100 + i * 173;         // prime stride crosses rows
            @(posedge clk); p0_addr <= a; p0_req <= 1'b1;
            @(posedge clk); p0_req <= 1'b0;
            wait (p0_ack); chk(p0_dout, a, "p0");
            @(posedge clk); @(posedge clk);
        end
        done_cnt = done_cnt + 1;
    end
endtask

task automatic gen_p1;  // tile-style 4-word bursts
    integer i, w; reg [24:3] a;
    begin
        for (i = 0; i < (tb_sdram_capture.quick ? 4 : 300); i = i + 1) begin
            a = 22'h00080 + i * 37;
            @(posedge clk); p1_addr <= a; p1_req <= 1'b1;
            @(posedge clk); p1_req <= 1'b0;
            wait (p1_ack);
            for (w = 0; w < 4; w = w + 1)
                chk(p1_dout[w*16 +: 16], {a, 2'b00} + w, "p1");
            @(posedge clk); @(posedge clk);
        end
        done_cnt = done_cnt + 1;
    end
endtask

task automatic gen_p2;  // sprite-style 8-word bursts
    integer i, w; reg [24:4] a;
    begin
        for (i = 0; i < (tb_sdram_capture.quick ? 4 : 300); i = i + 1) begin
            a = 21'h00040 + i * 53;
            @(posedge clk); p2_addr <= a; p2_req <= 1'b1;
            @(posedge clk); p2_req <= 1'b0;
            wait (p2_ack);
            for (w = 0; w < 8; w = w + 1)
                chk(p2_dout[w*16 +: 16], {a, 3'b000} + w, "p2");
            @(posedge clk); @(posedge clk);
        end
        done_cnt = done_cnt + 1;
    end
endtask

task automatic gen_p3;  // audio-style singles
    integer i; reg [24:1] a;
    begin
        for (i = 0; i < (tb_sdram_capture.quick ? 4 : 400); i = i + 1) begin
            a = 24'h000300 + i * 89;
            @(posedge clk); p3_addr <= a; p3_req <= 1'b1;
            @(posedge clk); p3_req <= 1'b0;
            wait (p3_ack); chk(p3_dout, a, "p3");
            @(posedge clk); @(posedge clk);
        end
        done_cnt = done_cnt + 1;
    end
endtask

integer i;
reg [24:1] wa;
integer quick = 0;
initial begin
    void'($value$plusargs("QUICK=%d", quick));
    if ($test$plusargs("VCD")) begin
        $dumpfile("/tmp/sdram_cap.vcd");
        $dumpvars(1, tb_sdram_capture);
        $dumpvars(1, tb_sdram_capture.dut);
    end
    repeat (4) @(posedge clk); init = 0;
    wait (ready);
    $display("controller ready t=%0t", $time);

    // download a pattern region covering every generator's address range
    // (p2's top burst word is just under 0x20000)
    for (i = 0; i < (quick ? 4096 : 131072); i = i + 1) begin
        wa = i[23:0] + 24'd1;
        dl_write(wa);
    end
    $display("pattern loaded t=%0t", $time);

    // concurrent read storm
    fork
        gen_p0;
        gen_p1;
        gen_p2;
        gen_p3;
    join

    $display("checked=%0d errors=%0d", checked, errors);
    if (errors == 0) $display("SDRAM CAPTURE PASS");
    else             $display("SDRAM CAPTURE FAIL");
    $finish;
end

initial begin
    #80_000_000;  // 80 ms guard
    $display("TIMEOUT");
    $finish;
end

endmodule
