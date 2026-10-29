`timescale 1ns/1ps
`default_nettype none

module instruction_memory #(
    parameter MEM_FILE = "",
    parameter integer WORDS = 256
) (
    input  wire [31:0] addr,
    output reg [31:0] instr
);
    reg [31:0] mem [0:WORDS-1];
    integer i;

    initial begin
        for (i = 0; i < WORDS; i = i + 1) begin
            mem[i] = 32'd0;
        end
        if (MEM_FILE != "") begin
            $readmemh(MEM_FILE, mem);
        end
    end

    always @* begin
        if (addr[31:2] < WORDS) begin
            instr = mem[addr[31:2]];
        end else begin
            instr = 32'd0;
        end
    end
endmodule

`default_nettype wire
