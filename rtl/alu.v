`timescale 1ns/1ps
`default_nettype none

module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  control,
    output reg [31:0] result,
    output wire       zero
);
    localparam [3:0] ALU_AND = 4'd0;
    localparam [3:0] ALU_OR  = 4'd1;
    localparam [3:0] ALU_ADD = 4'd2;
    localparam [3:0] ALU_SUB = 4'd6;
    localparam [3:0] ALU_SLT = 4'd7;

    always @* begin
        case (control)
            ALU_AND: result = a & b;
            ALU_OR : result = a | b;
            ALU_ADD: result = a + b;
            ALU_SUB: result = a - b;
            ALU_SLT: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            default: result = 32'd0;
        endcase
    end

    assign zero = (result == 32'd0);
endmodule

`default_nettype wire
