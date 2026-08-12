// MSM6253 ADC serial-read semantics under V60-like bus timing: cs is held
// for several clocks per transaction and the CPU latches read data at ack
// (the LAST cycle), not on the request edge.  Guards the post-shift sampling
// bug where the shifter advanced on the leading edge of cs and every byte
// came back rotated left by one — a centred 0x80 wheel read as 0x01, so
// OutRunners' car select spun right forever (Rad Mobile reads the same part
// on System 32).
`timescale 1ns/1ps
module tb_radm_msm6253;

reg clk = 0; always #5 clk = ~clk;
reg rst = 1;
reg cs = 0, we = 0;
reg [1:0] addr = 0;
wire dout_bit;
reg [7:0] an0 = 8'h80, an1 = 8'h00, an2 = 8'h5A, an3 = 8'hC3;

s32_msm6253 dut (
    .clk(clk), .rst(rst), .cs(cs), .we(we), .addr(addr),
    .dout_bit(dout_bit), .an0(an0), .an1(an1), .an2(an2), .an3(an3)
);

integer errors = 0;

// address_w: latch the addressed channel (held 2 cycles like a real access)
task bus_write(input [1:0] a);
    begin
        @(negedge clk); cs = 1; we = 1; addr = a;
        @(negedge clk); @(negedge clk);
        cs = 0; we = 0;
        @(negedge clk);
    end
endtask

// d7_r: one serial bit; cs held `hold` cycles, bit sampled on the last one
task bus_read_bit(input [1:0] a, input integer hold, output b);
    integer i;
    begin
        @(negedge clk); cs = 1; we = 0; addr = a;
        for (i = 0; i < hold - 1; i = i + 1) @(negedge clk);
        b = dout_bit;              // V60 samples m_rdata at ack
        @(negedge clk); cs = 0;
        @(negedge clk);            // inter-transaction idle
    end
endtask

task read_byte(input [1:0] a, input integer hold, output [7:0] v);
    integer i; reg b;
    begin
        v = 8'h00;
        for (i = 0; i < 8; i = i + 1) begin
            bus_read_bit(a, hold, b);
            v = {v[6:0], b};
        end
    end
endtask

task check(input [7:0] got, input [7:0] want, input [127:0] what);
    if (got !== want) begin
        errors = errors + 1;
        $display("FAIL %0s: got %02x want %02x", what, got, want);
    end
endtask

reg [7:0] got;
initial begin
    repeat (4) @(negedge clk); rst = 0; repeat (2) @(negedge clk);

    // 1) write-then-read per channel, MSB first, across transaction lengths
    bus_write(0); read_byte(0, 2, got); check(got, 8'h80, "ch0 msb-first");
    bus_write(1); read_byte(1, 3, got); check(got, 8'h00, "ch1 msb-first");
    bus_write(2); read_byte(2, 4, got); check(got, 8'h5A, "ch2 msb-first");
    bus_write(3); read_byte(3, 5, got); check(got, 8'hC3, "ch3 msb-first");

    // 2) OutRunners burst pattern: latch all four channels up front, then
    //    read the bytes much later — per-channel shifters must hold.
    an0 = 8'hA5; an1 = 8'h3C; an2 = 8'h81; an3 = 8'h7E;
    bus_write(0); bus_write(1); bus_write(2); bus_write(3);
    an0 = 8'hFF; an1 = 8'hFF; an2 = 8'hFF; an3 = 8'hFF; // inputs move on
    read_byte(3, 3, got); check(got, 8'h7E, "burst ch3");
    read_byte(0, 3, got); check(got, 8'hA5, "burst ch0");
    read_byte(2, 3, got); check(got, 8'h81, "burst ch2");
    read_byte(1, 3, got); check(got, 8'h3C, "burst ch1");

    // 3) free-running reload: consuming the 8th bit reloads the channel from
    //    its then-live input, so later bytes track the input without a fresh
    //    address_w.  Test 2's ch0 byte ended while an0 was FF; this byte ends
    //    while it is 42.
    an0 = 8'h42;
    read_byte(0, 3, got); check(got, 8'hFF, "reload uses live input");
    read_byte(0, 3, got); check(got, 8'h42, "free-running reload");

    if (errors == 0) $display("RAD MOBILE MSM6253 PASS");
    else             $display("RAD MOBILE MSM6253 FAIL (%0d errors)", errors);
    $finish;
end

endmodule
