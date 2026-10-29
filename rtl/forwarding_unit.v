`timescale 1ns/1ps
`default_nettype none

module forwarding_unit (
    input  wire       exmem_reg_write,
    input  wire       exmem_mem_read,
    input  wire [4:0] exmem_rd,
    input  wire       memwb_reg_write,
    input  wire [4:0] memwb_rd,
    input  wire [4:0] idex_rs,
    input  wire [4:0] idex_rt,
    output reg [1:0] forward_a,
    output reg [1:0] forward_b
);
    always @* begin
        forward_a = 2'b00;
        forward_b = 2'b00;

        // EX/MEM forwarding is not valid for a load because its data has not
        // returned from the cache yet.
        if (exmem_reg_write && !exmem_mem_read && (exmem_rd != 5'd0) &&
            (exmem_rd == idex_rs)) begin
            forward_a = 2'b10;
        end else if (memwb_reg_write && (memwb_rd != 5'd0) &&
                     (memwb_rd == idex_rs)) begin
            forward_a = 2'b01;
        end

        if (exmem_reg_write && !exmem_mem_read && (exmem_rd != 5'd0) &&
            (exmem_rd == idex_rt)) begin
            forward_b = 2'b10;
        end else if (memwb_reg_write && (memwb_rd != 5'd0) &&
                     (memwb_rd == idex_rt)) begin
            forward_b = 2'b01;
        end
    end
endmodule

`default_nettype wire
