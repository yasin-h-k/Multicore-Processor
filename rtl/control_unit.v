`timescale 1ns/1ps
`default_nettype none

module control_unit (
    input  wire [5:0] opcode,
    input  wire [5:0] funct,
    output reg       reg_dst,
    output reg       alu_src,
    output reg       mem_to_reg,
    output reg       reg_write,
    output reg       mem_read,
    output reg       mem_write,
    output reg       branch_eq,
    output reg       branch_ne,
    output reg       jump,
    output reg       imm_zero_extend,
    output reg [2:0] alu_op
);
    localparam [2:0] ALUOP_ADD   = 3'd0;
    localparam [2:0] ALUOP_SUB   = 3'd1;
    localparam [2:0] ALUOP_RTYPE = 3'd2;
    localparam [2:0] ALUOP_OR    = 3'd3;

    reg supported_rtype;

    always @* begin
        supported_rtype = (funct == 6'h20) || (funct == 6'h22) ||
                          (funct == 6'h24) || (funct == 6'h25) ||
                          (funct == 6'h2A);

        reg_dst         = 1'b0;
        alu_src         = 1'b0;
        mem_to_reg      = 1'b0;
        reg_write       = 1'b0;
        mem_read        = 1'b0;
        mem_write       = 1'b0;
        branch_eq       = 1'b0;
        branch_ne       = 1'b0;
        jump            = 1'b0;
        imm_zero_extend = 1'b0;
        alu_op          = ALUOP_ADD;

        case (opcode)
            6'h00: begin // R type
                reg_dst   = 1'b1;
                reg_write = supported_rtype;
                alu_op    = ALUOP_RTYPE;
            end
            6'h08: begin // addi
                alu_src   = 1'b1;
                reg_write = 1'b1;
                alu_op    = ALUOP_ADD;
            end
            6'h0D: begin // ori
                alu_src         = 1'b1;
                reg_write       = 1'b1;
                imm_zero_extend = 1'b1;
                alu_op          = ALUOP_OR;
            end
            6'h23: begin // lw
                alu_src    = 1'b1;
                mem_to_reg = 1'b1;
                reg_write  = 1'b1;
                mem_read   = 1'b1;
                alu_op     = ALUOP_ADD;
            end
            6'h2B: begin // sw
                alu_src   = 1'b1;
                mem_write = 1'b1;
                alu_op    = ALUOP_ADD;
            end
            6'h04: begin // beq
                branch_eq = 1'b1;
                alu_op    = ALUOP_SUB;
            end
            6'h05: begin // bne
                branch_ne = 1'b1;
                alu_op    = ALUOP_SUB;
            end
            6'h02: begin // j
                jump = 1'b1;
            end
            default: begin
                // Illegal/unsupported instructions behave as NOPs.
            end
        endcase
    end
endmodule

`default_nettype wire
