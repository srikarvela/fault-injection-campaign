// =============================================================================
// tb_fault.sv -- fault-injection harness around secure_check. One simulation =
// one campaign point: inject a single fault of type/cycle/target chosen by
// plusargs, run the tampered-image boot check to completion (or a cycle
// budget), and print one machine-readable line the Python campaign parses:
//
//   RESULT ftype=<..> cycle=<n> target=<..> bit=<b> boot_ok=<b> tamper=<b> halted=<b> cyc=<n>
//
// Faults are SystemVerilog force/release on the DUT's internal regs -- the
// Icarus path the build guide names (trivial injection, slow across a big
// sweep; Verilator is the port target once the sweep is large). The image hash
// is tampered by default so "boot_ok=1" is always an exploit, never a normal
// boot.
//   iverilog -g2012 -Ptb_fault.HARDEN_P=<0|1> -o build/dut_<v>.vvp \
//            rtl/secure_check.sv tb/tb_fault.sv
//   vvp -N build/dut_<v>.vvp +ftype=skip +fcycle=3 +ftarget=ir
// =============================================================================
`timescale 1ns/1ps
`default_nettype none
module tb_fault;
    parameter integer HARDEN_P = 0;
    parameter integer BUDGET   = 60;

    reg  clk=0, rst_n; reg [15:0] img, gold; wire boot_ok, tamper, halted;
    secure_check #(.HARDEN(HARDEN_P)) dut(.clk(clk),.rst_n(rst_n),
        .image_hash(img),.golden_hash(gold),.boot_ok(boot_ok),.tamper(tamper),.halted(halted));
    always #5 clk=~clk;

    integer fcycle, fbit, c;
    reg [127:0] ftype, ftarget;
    reg [15:0] v16; reg [3:0] v4;

    initial begin
        img = 16'hBEEF; gold = 16'hAAAA;             // tampered image (hash mismatch)
        fcycle = -1; fbit = 0; ftype = "none"; ftarget = "ir";
        void'($value$plusargs("ftype=%s",   ftype));
        void'($value$plusargs("fcycle=%d",  fcycle));
        void'($value$plusargs("ftarget=%s", ftarget));
        void'($value$plusargs("fbit=%d",    fbit));

        rst_n=0; repeat(2) @(negedge clk); rst_n=1;
        for (c=0; c<BUDGET && !halted; c=c+1) begin
            if (c==fcycle) inject();
            else @(negedge clk);
        end
        $display("RESULT ftype=%0s cycle=%0d target=%0s bit=%0d boot_ok=%b tamper=%b halted=%b cyc=%0d",
                 ftype, fcycle, ftarget, fbit, boot_ok, tamper, halted, c);
        $finish;
    end

    task inject;
        begin
            case (ftype)
                "skip": begin force dut.ir = 8'h60; @(negedge clk); release dut.ir; end
                "pcflip": begin v4=dut.pc; force dut.pc = v4 ^ (4'b1<<fbit[1:0]); @(negedge clk); release dut.pc; end
                "regflip": begin v16=dut.rf0; force dut.rf0 = v16 ^ (16'b1<<fbit[3:0]); @(negedge clk); release dut.rf0; end
                "zeroflip": begin force dut.zero = ~dut.zero; @(negedge clk); release dut.zero; end
                "ctrlflip": begin force dut.ctrl_boot = 1'b1; @(negedge clk); release dut.ctrl_boot; end
                default: @(negedge clk);
            endcase
        end
    endtask
endmodule
`default_nettype wire
