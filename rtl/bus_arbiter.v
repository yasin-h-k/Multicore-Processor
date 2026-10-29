`timescale 1ns/1ps
`default_nettype none

module bus_arbiter (
    input  wire         clk,
    input  wire         reset,

    input  wire         c0_req,
    input  wire [1:0]   c0_cmd,
    input  wire [31:0]  c0_addr,
    input  wire [127:0] c0_wdata,
    output reg         c0_done,
    output reg [127:0] c0_rdata,
    output reg         c0_shared,
    output reg         c0_grant_pulse,

    input  wire         c1_req,
    input  wire [1:0]   c1_cmd,
    input  wire [31:0]  c1_addr,
    input  wire [127:0] c1_wdata,
    output reg         c1_done,
    output reg [127:0] c1_rdata,
    output reg         c1_shared,
    output reg         c1_grant_pulse,

    output reg         snoop0_valid,
    output reg [1:0]   snoop0_cmd,
    output reg [31:0]  snoop0_addr,
    input  wire         snoop0_hit,
    input  wire         snoop0_modified,
    input  wire [127:0] snoop0_data,

    output reg         snoop1_valid,
    output reg [1:0]   snoop1_cmd,
    output reg [31:0]  snoop1_addr,
    input  wire         snoop1_hit,
    input  wire         snoop1_modified,
    input  wire [127:0] snoop1_data,

    output reg         mem_req,
    output reg         mem_we,
    output reg [31:0]  mem_addr,
    output reg [127:0] mem_wdata,
    input  wire [127:0] mem_rdata,
    input  wire         mem_ready,

    output reg [2:0]   debug_state,
    output reg         debug_owner,
    output reg [1:0]   debug_cmd
);
    localparam [1:0] BUS_RD   = 2'b00;
    localparam [1:0] BUS_RDX  = 2'b01;
    localparam [1:0] BUS_UPGR = 2'b10;
    localparam [1:0] BUS_WB   = 2'b11;

    localparam [2:0] A_IDLE      = 3'd0;
    localparam [2:0] A_SNOOP     = 3'd1;
    localparam [2:0] A_MEM_READ  = 3'd2;
    localparam [2:0] A_MEM_WRITE = 3'd3;
    localparam [2:0] A_RESP      = 3'd4;

    reg [2:0] state;
    reg owner;
    reg [1:0] current_cmd;
    reg [31:0] current_addr;
    reg [127:0] response_data;
    reg response_shared;
    reg [127:0] memory_write_data;

    // The round-robin pointer changes only when both requesters compete in the
    // same arbitration decision. Single requests do not consume the alternate
    // priority, which makes repeated simultaneous competitions visibly fair.
    reg last_simultaneous_grant;

    reg other_hit;
    reg other_modified;
    reg [127:0] other_data;

    always @* begin
        other_hit      = owner ? snoop0_hit      : snoop1_hit;
        other_modified = owner ? snoop0_modified : snoop1_modified;
        other_data     = owner ? snoop0_data     : snoop1_data;

        c0_done   = 1'b0;
        c1_done   = 1'b0;
        c0_rdata  = response_data;
        c1_rdata  = response_data;
        c0_shared = response_shared;
        c1_shared = response_shared;

        mem_req   = 1'b0;
        mem_we    = 1'b0;
        mem_addr  = current_addr;
        mem_wdata = memory_write_data;

        debug_state = state;
        debug_owner = owner;
        debug_cmd   = current_cmd;

        case (state)
            A_SNOOP: begin
                // Snoop outputs are generated in a separate combinational
                // block below to avoid transient zero/one glitches.
            end
            A_MEM_READ: begin
                mem_req  = 1'b1;
                mem_we   = 1'b0;
                mem_addr = current_addr;
            end
            A_MEM_WRITE: begin
                mem_req   = 1'b1;
                mem_we    = 1'b1;
                mem_addr  = current_addr;
                mem_wdata = memory_write_data;
            end
            A_RESP: begin
                if (owner == 1'b0) begin
                    c0_done = 1'b1;
                end else begin
                    c1_done = 1'b1;
                end
            end
            default: begin
            end
        endcase
    end

    // Keep the snoop broadcast in its own combinational block and assign
    // every output exactly once.  The peer cache's snoop_hit returns to this
    // arbiter combinationally; assigning snoop_valid first to 0 and then to 1
    // in the same evaluation would cause an endless delta-cycle oscillation
    // whenever the peer actually has the requested line.
    always @* begin
        snoop0_valid = (state == A_SNOOP) && (owner == 1'b1);
        snoop1_valid = (state == A_SNOOP) && (owner == 1'b0);
        snoop0_cmd   = current_cmd;
        snoop1_cmd   = current_cmd;
        snoop0_addr  = current_addr;
        snoop1_addr  = current_addr;
    end

    always @(posedge clk) begin
        if (reset) begin
            state                    <= A_IDLE;
            owner                    <= 1'b0;
            current_cmd              <= BUS_RD;
            current_addr             <= 32'd0;
            response_data            <= 128'd0;
            response_shared          <= 1'b0;
            memory_write_data        <= 128'd0;
            last_simultaneous_grant  <= 1'b1; // Core 0 wins first tie.
            c0_grant_pulse           <= 1'b0;
            c1_grant_pulse           <= 1'b0;
        end else begin
            c0_grant_pulse <= 1'b0;
            c1_grant_pulse <= 1'b0;

            case (state)
                A_IDLE: begin
                    if (c0_req || c1_req) begin
                        if (c0_req && c1_req) begin
                            owner <= ~last_simultaneous_grant;
                            last_simultaneous_grant <= ~last_simultaneous_grant;
                            if (~last_simultaneous_grant == 1'b0) begin
                                current_cmd   <= c0_cmd;
                                current_addr  <= {c0_addr[31:4], 4'b0000};
                                c0_grant_pulse <= 1'b1;
                                if (c0_cmd == BUS_WB) begin
                                    memory_write_data <= c0_wdata;
                                end
                            end else begin
                                current_cmd   <= c1_cmd;
                                current_addr  <= {c1_addr[31:4], 4'b0000};
                                c1_grant_pulse <= 1'b1;
                                if (c1_cmd == BUS_WB) begin
                                    memory_write_data <= c1_wdata;
                                end
                            end
                        end else if (c0_req) begin
                            owner          <= 1'b0;
                            current_cmd    <= c0_cmd;
                            current_addr   <= {c0_addr[31:4], 4'b0000};
                            c0_grant_pulse <= 1'b1;
                            if (c0_cmd == BUS_WB) begin
                                memory_write_data <= c0_wdata;
                            end
                        end else begin
                            owner          <= 1'b1;
                            current_cmd    <= c1_cmd;
                            current_addr   <= {c1_addr[31:4], 4'b0000};
                            c1_grant_pulse <= 1'b1;
                            if (c1_cmd == BUS_WB) begin
                                memory_write_data <= c1_wdata;
                            end
                        end

                        response_data   <= 128'd0;
                        response_shared <= 1'b0;
                        if ((c0_req && !c1_req && (c0_cmd == BUS_WB)) ||
                            (c1_req && !c0_req && (c1_cmd == BUS_WB))) begin
                            state <= A_MEM_WRITE;
                        end else if (c0_req && c1_req) begin
                            // The chosen command is determined from the same
                            // round-robin expression used above.
                            if ((~last_simultaneous_grant == 1'b0 && c0_cmd == BUS_WB) ||
                                (~last_simultaneous_grant == 1'b1 && c1_cmd == BUS_WB)) begin
                                state <= A_MEM_WRITE;
                            end else begin
                                state <= A_SNOOP;
                            end
                        end else begin
                            state <= A_SNOOP;
                        end
                    end
                end

                A_SNOOP: begin
                    if (current_cmd == BUS_UPGR) begin
                        response_shared <= other_hit;
                        response_data   <= 128'd0;
                        state           <= A_RESP;
                    end else if (other_hit) begin
                        response_data   <= other_data;
                        response_shared <= (current_cmd == BUS_RD);
                        if (other_modified) begin
                            // Modified intervention: memory is first updated
                            // with the newest block, then the requester receives
                            // that same block. Stale memory is never returned.
                            memory_write_data <= other_data;
                            state <= A_MEM_WRITE;
                        end else begin
                            // Clean E/S data can be transferred cache-to-cache.
                            state <= A_RESP;
                        end
                    end else begin
                        response_shared <= 1'b0;
                        state <= A_MEM_READ;
                    end
                end

                A_MEM_READ: begin
                    if (mem_ready) begin
                        response_data   <= mem_rdata;
                        response_shared <= 1'b0;
                        state <= A_RESP;
                    end
                end

                A_MEM_WRITE: begin
                    if (mem_ready) begin
                        state <= A_RESP;
                    end
                end

                A_RESP: begin
                    state <= A_IDLE;
                end

                default: state <= A_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
