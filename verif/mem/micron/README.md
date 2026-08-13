# Micron SDR SDRAM simulation model

`sdr.sv` / `sdr_parameters.vh` are Micron's official SDR SDRAM Verilog
simulation model (v2.3, distributed by Micron for verification use), obtained
via the MIT-licensed https://github.com/agg23/sdram-controller test suite.
Local changes: `Debug` tied 0 for quiet regression runs; parameters ship
preconfigured for sg75 / den512Mb (matches MiSTer 128MB modules).

Used by `verif/mem/tb_sdram_capture.sv` to validate the SDRAM controller's
read-capture timing against datasheet-accurate tAC/tOH behaviour — the model
must run under an event-driven simulator (Icarus); Verilator's --timing mode
mis-executes its delayed sampling.
