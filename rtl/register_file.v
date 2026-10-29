`timescale 1ns/1ps
`default_nettype none

module register_file (
    input  wire        clk,
    input  wire        reset,
    input  wire        we,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata,
    input  wire [4:0]  raddr1,
    input  wire [4:0]  raddr2,
    output reg [31:0] rdata1,
    output reg [31:0] rdata2
);
    reg [31:0] regs [0:31];
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'd0;
            end
        end else begin
            if (we && (waddr != 5'd0)) begin
                regs[waddr] <= wdata;
            end
            regs[0] <= 32'd0;
        end
    end

    always @* begin
        if (raddr1 == 5'd0) begin
            rdata1 = 32'd0;
        end else if (we && (waddr == raddr1) && (waddr != 5'd0)) begin
            rdata1 = wdata;
        end else begin
            rdata1 = regs[raddr1];
        end

        if (raddr2 == 5'd0) begin
            rdata2 = 32'd0;
        end else if (we && (waddr == raddr2) && (waddr != 5'd0)) begin
            rdata2 = wdata;
        end else begin
            rdata2 = regs[raddr2];
        end
    end
endmodule

`default_nettype wire
