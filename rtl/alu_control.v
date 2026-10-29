`timescale 1ns/1ps
`default_nettype none

module alu_control (
    input  wire [2:0] alu_op,
    input  wire [5:0] funct,
    output reg [3:0] alu_ctrl
);
    localparam [2:0] ALUOP_ADD   = 3'd0;
    localparam [2:0] ALUOP_SUB   = 3'd1;
    localparam [2:0] ALUOP_RTYPE = 3'd2;
    localparam [2:0] ALUOP_OR    = 3'd3;

    localparam [3:0] ALU_AND = 4'd0;
    localparam [3:0] ALU_OR  = 4'd1;
    localparam [3:0] ALU_ADD = 4'd2;
    localparam [3:0] ALU_SUB = 4'd6;
    localparam [3:0] ALU_SLT = 4'd7;

    always @* begin
        alu_ctrl = ALU_ADD;
        case (alu_op)
            ALUOP_ADD: alu_ctrl = ALU_ADD;
            ALUOP_SUB: alu_ctrl = ALU_SUB;
            ALUOP_OR : alu_ctrl = ALU_OR;
            ALUOP_RTYPE: begin
                case (funct)
                    6'h20: alu_ctrl = ALU_ADD; // add
                    6'h22: alu_ctrl = ALU_SUB; // sub
                    6'h24: alu_ctrl = ALU_AND; // and
                    6'h25: alu_ctrl = ALU_OR;  // or
                    6'h2A: alu_ctrl = ALU_SLT; // slt
                    default: alu_ctrl = ALU_ADD;
                endcase
            end
            default: alu_ctrl = ALU_ADD;
        endcase
    end
endmodule

`default_nettype wire
