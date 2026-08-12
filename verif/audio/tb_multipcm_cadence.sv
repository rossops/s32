//============================================================================
//  MultiPCM cadence test: the GEW8 slot schedule must emit one stereo sample
//  every 224 CE periods no matter how slow the sample ROM is.  The original
//  sequencer stalled the whole 28-slot frame on every ROM round trip, so
//  SDRAM contention time-dilated the mix (dropouts, and a full octave pitch
//  drop at 2x stretch) on real hardware.  Two runs here: ROM ack in 2 clks
//  (must also produce correct, non-zero audio from a keyed-on ramp sample)
//  and ROM ack in 60 clks >> the 8-CE slot slice (cadence must not budge).
//============================================================================
`timescale 1ns/1ps

module tb_multipcm_cadence;

reg clk = 0;
always #10 clk = ~clk;

// ce at clk/2 so ROM latency in clks spans CE boundaries
reg [0:0] cediv = 0;
always @(posedge clk) cediv <= cediv + 1'b1;
wire ce = (cediv == 1'd0);

reg rst = 1;

reg        cs = 0, we = 0;
reg  [1:0] waddr = 0;
reg  [7:0] wdata = 0;

wire        rom_req;
wire [21:0] rom_addr;
reg   [7:0] rom_data;
reg         rom_ack = 0;

wire signed [15:0] out_l, out_r;

s32_multipcm dut (
    .clk(clk), .ce(ce), .rst(rst),
    .cs(cs), .we(we), .addr(waddr), .wdata(wdata), .rdata(),
    .rom_req(rom_req), .rom_addr(rom_addr), .rom_data(rom_data),
    .rom_ack(rom_ack),
    .bank_lo(3'd0), .bank_hi(3'd0),
    .out_l(out_l), .out_r(out_r)
);

// ROM model: descriptor 0 at bytes 0..11 (start=0x001000, loop=0,
// end-stored=0xff00 so length 0x100), sample data = ramp at 0x1000.
integer rom_latency = 2;
integer lat_cnt = 0;
reg pending = 0;
reg [21:0] pend_addr;
always @(posedge clk) begin
    rom_ack <= 0;
    if (rom_req && !pending && !rom_ack) begin
        pending <= 1;
        pend_addr <= rom_addr;
        lat_cnt <= 0;
    end
    else if (pending) begin
        lat_cnt <= lat_cnt + 1;
        if (lat_cnt >= rom_latency) begin
            pending <= 0;
            rom_ack <= 1;
            case (pend_addr)
                22'h0: rom_data <= 8'h00;      // start[21:16]
                22'h1: rom_data <= 8'h10;      // start[15:8]
                22'h2: rom_data <= 8'h00;      // start[7:0]
                22'h3: rom_data <= 8'h00;      // loop hi
                22'h4: rom_data <= 8'h00;      // loop lo
                22'h5: rom_data <= 8'hff;      // end hi (len = 0x10000-0xff00)
                22'h6: rom_data <= 8'h00;      // end lo
                default:
                    if (pend_addr >= 22'h1000 && pend_addr < 22'h1100)
                        rom_data <= 8'h40 + pend_addr[5:0]; // audible ramp
                    else
                        rom_data <= 8'h00;
            endcase
        end
    end
end

task wr(input [1:0] a, input [7:0] d);
begin
    @(posedge clk); cs <= 1; we <= 1; waddr <= a; wdata <= d;
    @(posedge clk); cs <= 0; we <= 0;
end
endtask

// cadence checker: distance between out_l update strobes in CE counts
integer ce_cnt = 0;
always @(posedge clk) if (ce) ce_cnt = ce_cnt + 1;

integer last_ce = -1, ivals = 0, bad = 0;
integer nonzero = 0;
reg signed [15:0] out_l_d = 0;
reg started = 0;
always @(posedge clk) begin
    if (ce && dut.slot == 5'd0 && dut.tick == 3'd0) begin
        if (started) begin
            if (last_ce >= 0) begin
                ivals = ivals + 1;
                if (ce_cnt - last_ce != 224) begin
                    bad = bad + 1;
                    $display("[cadence] interval %0d CEs (expected 224)",
                        ce_cnt - last_ce);
                end
            end
            last_ce = ce_cnt;
        end
    end
    if (out_l != out_l_d) begin
        out_l_d <= out_l;
        if (out_l != 0) nonzero = nonzero + 1;
    end
end

integer pass1_nonzero;
initial begin
    // ---- run 1: fast ROM, expect audio + fixed cadence ----
    repeat (8) @(posedge clk);
    rst = 0;
    repeat (20) @(posedge clk);
    // slot 0: sample 0, pitch oct=1/pitch=0 (step 1.0), TL 0, pan center
    wr(2'd1, 8'h00);           // select channel 0
    wr(2'd2, 8'd0); wr(2'd0, 8'h00);  // reg0 pan = 0 (both full)
    wr(2'd2, 8'd1); wr(2'd0, 8'h00);  // reg1 sample low = 0
    wr(2'd2, 8'd2); wr(2'd0, 8'h00);  // reg2 pitch low / sample bit8
    wr(2'd2, 8'd3); wr(2'd0, 8'h10);  // reg3 oct=1, pitch hi = 0
    wr(2'd2, 8'd5); wr(2'd0, 8'h00);  // reg5 TL = 0
    wr(2'd2, 8'd4); wr(2'd0, 8'h80);  // reg4 key on
    repeat (2000) @(posedge clk);
    started = 1; last_ce = -1;
    repeat (40000) @(posedge clk);
    started = 0;
    pass1_nonzero = nonzero;
    $display("run1: intervals=%0d bad=%0d nonzero_out=%0d", ivals, bad, nonzero);

    // ---- run 2: pathological ROM latency, cadence must hold ----
    rom_latency = 60;
    repeat (2000) @(posedge clk);
    started = 1; last_ce = -1;
    repeat (60000) @(posedge clk);
    started = 0;
    $display("run2: intervals=%0d bad=%0d", ivals, bad);

    if (bad == 0 && ivals > 200 && pass1_nonzero > 20)
        $display("MULTIPCM CADENCE PASS");
    else
        $display("MULTIPCM CADENCE FAIL");
    $finish;
end

endmodule
