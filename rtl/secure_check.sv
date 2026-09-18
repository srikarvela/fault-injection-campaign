// =============================================================================
// secure_check.sv -- a minimal secure-boot check, the payload the fault
// campaign attacks. Models D2's signature-check branch: compare image hash to
// golden, then branch to BOOT or to HALT+tamper. One instruction per cycle
// through a forcible instruction register `ir` (= rom[pc], overridable), a PC,
// a 2-entry register file, and a zero flag -- enough real control state that
// instruction-skip, PC corruption, register bit-flip and control-line flip all
// mean what they mean on a real core. Every injectable signal (ir, pc, rf,
// zero, zero2, cfi, ctrl_boot) is a plain reg reachable by hierarchical force.
//
// HARDEN=0 baseline: one compare, one branch, one halt -> a single skipped
//                    HALT falls through to BOOT (the classic bypass).
// HARDEN=1 hardened: duplicated compare (second encoding), a control-flow
//                    integrity counter that must reach its final value, a
//                    redundant refuse, and a guarded boot gate.
// =============================================================================
`default_nettype none
module secure_check #(parameter integer HARDEN = 0) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] image_hash,
    input  wire [15:0] golden_hash,
    output reg         boot_ok,
    output reg         tamper,
    output reg         halted
);
    localparam [3:0] OP_LDIH=4'd0, OP_LDIG=4'd1, OP_CMP=4'd2, OP_BEQ=4'd3,
                     OP_BOOT=4'd4, OP_HALT=4'd5, OP_NOP=4'd6, OP_CMP2=4'd7,
                     OP_BOOTG=4'd8, OP_CFICHK=4'd9;

    reg [7:0] rom [0:15];
    integer i;
    initial begin
        for (i=0;i<16;i=i+1) rom[i] = {OP_NOP,4'd0};
        if (HARDEN==0) begin
            rom[0]={OP_LDIH,4'd0}; rom[1]={OP_LDIG,4'd1}; rom[2]={OP_CMP,4'd0};
            rom[3]={OP_BEQ,4'd5};  rom[4]={OP_HALT,4'd0}; rom[5]={OP_BOOT,4'd0};
        end else begin
            rom[0]={OP_LDIH,4'd0};  rom[1]={OP_LDIG,4'd1};  rom[2]={OP_CMP,4'd0};
            rom[3]={OP_BEQ,4'd6};   rom[4]={OP_HALT,4'd0};  rom[5]={OP_HALT,4'd0};
            rom[6]={OP_CMP2,4'd0};  rom[7]={OP_CFICHK,4'd0}; rom[8]={OP_BOOTG,4'd0};
        end
    end

    reg [3:0]  pc;
    reg [7:0]  ir;                          // forcible instruction register
    reg [15:0] rf0, rf1;
    reg        zero, zero2, cfi_ok;
    reg [3:0]  cfi;
    reg        ctrl_boot;                   // decoded "commit boot" line (forcible)
    localparam [3:0] CFI_EXPECT = 4'd5;

    always @(*) ir = rom[pc];               // current instruction; force overrides
    wire [3:0] op  = ir[7:4];
    wire [3:0] arg = ir[3:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc<=4'd0; boot_ok<=1'b0; tamper<=1'b0; halted<=1'b0;
            zero<=1'b0; zero2<=1'b0; cfi_ok<=1'b0; cfi<=4'd0; ctrl_boot<=1'b0;
            rf0<=16'd0; rf1<=16'd0;
        end else if (!halted) begin
            ctrl_boot <= 1'b0;
            // CFI counter bumps only on a real executed instruction, NOT on NOP
            // / a skipped instruction, so a skip leaves cfi short of CFI_EXPECT.
            case (op)
                OP_LDIH: begin rf0<=image_hash;  cfi<=cfi+4'd1; pc<=pc+4'd1; end
                OP_LDIG: begin rf1<=golden_hash; cfi<=cfi+4'd1; pc<=pc+4'd1; end
                OP_CMP : begin zero <=(rf0==rf1); cfi<=cfi+4'd1; pc<=pc+4'd1; end
                OP_CMP2: begin zero2<=(rf0==rf1); cfi<=cfi+4'd1; pc<=pc+4'd1; end
                OP_BEQ : begin cfi<=cfi+4'd1; pc <= zero ? arg : pc+4'd1; end
                OP_CFICHK: begin cfi_ok<=(cfi>=CFI_EXPECT); cfi<=cfi+4'd1; pc<=pc+4'd1; end
                OP_HALT: begin tamper<=1'b1; halted<=1'b1; end
                OP_BOOT: begin ctrl_boot<=1'b1; boot_ok<=1'b1; halted<=1'b1; end
                OP_BOOTG: begin
                    if (zero && zero2 && cfi_ok) begin ctrl_boot<=1'b1; boot_ok<=1'b1; end
                    else tamper<=1'b1;
                    halted<=1'b1;
                end
                default: pc<=pc+4'd1;       // NOP / skipped instruction: no cfi bump
            endcase
            if (ctrl_boot) boot_ok<=1'b1;   // a forced control line also commits boot
        end
    end
endmodule
`default_nettype wire
