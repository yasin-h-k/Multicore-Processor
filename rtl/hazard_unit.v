`timescale 1ns/1ps
`default_nettype none

module hazard_unit (
    input  wire       idex_mem_read,
    input  wire [4:0] idex_rt,
    input  wire [31:0] ifid_instr,
    output reg       load_use_stall
);
    reg [5:0] opcode;
    reg [4:0] rs;
    reg [4:0] rt;
    reg uses_rs;
    reg uses_rt;

    always @* begin
        opcode = ifid_instr[31:26];
        rs     = ifid_instr[25:21];
        rt     = ifid_instr[20:16];
        uses_rs = 1'b0;
        uses_rt = 1'b0;

        case (opcode)
            6'h00: begin uses_rs = 1'b1; uses_rt = 1'b1; end // R type
            6'h08: begin uses_rs = 1'b1; uses_rt = 1'b0; end // addi
            6'h0D: begin uses_rs = 1'b1; uses_rt = 1'b0; end // ori
            6'h23: begin uses_rs = 1'b1; uses_rt = 1'b0; end // lw
            6'h2B: begin uses_rs = 1'b1; uses_rt = 1'b1; end // sw
            6'h04: begin uses_rs = 1'b1; uses_rt = 1'b1; end // beq
            6'h05: begin uses_rs = 1'b1; uses_rt = 1'b1; end // bne
            default: begin uses_rs = 1'b0; uses_rt = 1'b0; end
        endcase

        load_use_stall = idex_mem_read && (idex_rt != 5'd0) &&
                         ((uses_rs && (idex_rt == rs)) ||
                          (uses_rt && (idex_rt == rt)));
    end
endmodule

`default_nettype wire
