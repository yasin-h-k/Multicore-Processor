`timescale 1ns/1ps
`default_nettype none

module shared_main_memory #(
    parameter integer BLOCKS = 256,
    parameter integer LATENCY = 3,
    parameter INIT_FILE = ""
) (
    input  wire         clk,
    input  wire         reset,
    input  wire         mem_req,
    input  wire         mem_we,
    input  wire [31:0]  mem_addr,
    input  wire [127:0] mem_wdata,
    output reg [127:0] mem_rdata,
    output wire        mem_ready,
    output reg         debug_write_pulse,
    output reg         debug_read_pulse
);
    localparam [1:0] M_IDLE = 2'd0;
    localparam [1:0] M_BUSY = 2'd1;
    localparam [1:0] M_RESP = 2'd2;

    reg [127:0] mem [0:BLOCKS-1];
    reg [1:0] state;
    reg pending_we;
    reg [31:0] pending_addr;
    reg [127:0] pending_wdata;
    integer count;
    integer i;

    initial begin
        for (i = 0; i < BLOCKS; i = i + 1) begin
            mem[i] = 128'd0;
        end
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    assign mem_ready = (state == M_RESP);

    always @(posedge clk) begin
        if (reset) begin
            state             <= M_IDLE;
            pending_we        <= 1'b0;
            pending_addr      <= 32'd0;
            pending_wdata     <= 128'd0;
            mem_rdata         <= 128'd0;
            count             <= 0;
            debug_write_pulse <= 1'b0;
            debug_read_pulse  <= 1'b0;
        end else begin
            debug_write_pulse <= 1'b0;
            debug_read_pulse  <= 1'b0;

            case (state)
                M_IDLE: begin
                    if (mem_req) begin
                        pending_we    <= mem_we;
                        pending_addr  <= {mem_addr[31:4], 4'b0000};
                        pending_wdata <= mem_wdata;
                        count         <= LATENCY;
                        state         <= M_BUSY;
                    end
                end

                M_BUSY: begin
                    if (count > 1) begin
                        count <= count - 1;
                    end else begin
                        if (pending_addr[31:12] == 20'd0) begin
                            if (pending_we) begin
                                mem[pending_addr[11:4]] <= pending_wdata;
                                debug_write_pulse <= 1'b1;
                            end else begin
                                mem_rdata <= mem[pending_addr[11:4]];
                                debug_read_pulse <= 1'b1;
                            end
                        end else if (!pending_we) begin
                            mem_rdata <= 128'd0;
                            debug_read_pulse <= 1'b1;
                        end
                        state <= M_RESP;
                    end
                end

                M_RESP: begin
                    // Hold ready until the arbiter removes mem_req.
                    if (!mem_req) begin
                        state <= M_IDLE;
                    end
                end

                default: state <= M_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
