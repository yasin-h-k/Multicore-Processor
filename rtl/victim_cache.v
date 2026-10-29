`timescale 1ns/1ps
`default_nettype none

// Four-entry fully-associative victim cache.
// Each entry stores the complete block address, 128-bit data, and MESI state.
// The L1 controller owns insertion/swap policy; this module independently
// participates in all bus snoops so coherence covers blocks outside L1 too.
module victim_cache #(
    parameter integer ENTRIES = 4
) (
    input  wire         clk,
    input  wire         reset,
    input  wire         enable,

    // Fully-associative local lookup used before an L1 miss reaches the bus.
    input  wire [31:0]  lookup_addr,
    output reg          lookup_hit,
    output reg [1:0]    lookup_index,
    output reg [1:0]    lookup_state,
    output reg [127:0]  lookup_data,

    // Current FIFO replacement candidate.
    output wire [1:0]   replacement_index,
    output wire         replacement_valid,
    output wire [27:0]  replacement_block_addr,
    output wire [1:0]   replacement_state,
    output wire [127:0] replacement_data,

    // Management interface from the private L1 controller.
    input  wire         manager_write,
    input  wire [1:0]   manager_index,
    input  wire [27:0]  manager_block_addr,
    input  wire [127:0] manager_data,
    input  wire [1:0]   manager_state,
    input  wire         manager_invalidate,
    input  wire [1:0]   manager_invalidate_index,
    input  wire         manager_advance_fifo,

    // Shared-bus snoop interface.
    input  wire         snoop_valid,
    input  wire [1:0]   snoop_cmd,
    input  wire [31:0]  snoop_addr,
    output reg          snoop_hit,
    output reg          snoop_modified,
    output reg [127:0]  snoop_data,

    // Debug/status.
    output wire [1:0]   debug_fifo_pointer
);
    localparam [1:0] MESI_I = 2'b00;
    localparam [1:0] MESI_S = 2'b01;
    localparam [1:0] MESI_E = 2'b10;
    localparam [1:0] MESI_M = 2'b11;

    localparam [1:0] BUS_RD   = 2'b00;
    localparam [1:0] BUS_RDX  = 2'b01;
    localparam [1:0] BUS_UPGR = 2'b10;

    // These arrays intentionally remain visible for self-checking testbenches.
    reg [27:0]  block_addr [0:ENTRIES-1];
    reg [127:0] data_block [0:ENTRIES-1];
    reg [1:0]   mesi_state [0:ENTRIES-1];
    reg [1:0]   fifo_pointer;

    integer i;
    reg lookup_found;
    reg snoop_found;
    reg [1:0] snoop_index;
    reg snoop_hit_next;
    reg snoop_modified_next;
    reg [127:0] snoop_data_next;

    assign replacement_index      = fifo_pointer;
    assign replacement_valid      = enable && (mesi_state[fifo_pointer] != MESI_I);
    assign replacement_block_addr = block_addr[fifo_pointer];
    assign replacement_state      = mesi_state[fifo_pointer];
    assign replacement_data       = data_block[fifo_pointer];
    assign debug_fifo_pointer      = fifo_pointer;

    // Search all four entries in parallel. The first matching entry wins;
    // duplicates are prevented by the L1 swap/insertion rules.
    always @* begin
        lookup_hit   = 1'b0;
        lookup_index = 2'd0;
        lookup_state = MESI_I;
        lookup_data  = 128'd0;
        lookup_found = 1'b0;
        for (i = 0; i < ENTRIES; i = i + 1) begin
            if (!lookup_found && enable &&
                (mesi_state[i] != MESI_I) &&
                (block_addr[i] == lookup_addr[31:4])) begin
                lookup_hit   = 1'b1;
                lookup_index = i[1:0];
                lookup_state = mesi_state[i];
                lookup_data  = data_block[i];
                lookup_found = 1'b1;
            end
        end
    end

    // Victim-cache entries are coherent participants, not merely a local
    // miss buffer. A snoop can therefore obtain or invalidate a victim entry.
    always @* begin
        // Compute through private temporaries and drive each external snoop
        // output exactly once. This avoids zero-time 0->1 output glitches in
        // event-driven simulators when the arbiter consumes snoop_hit.
        snoop_hit_next      = 1'b0;
        snoop_modified_next = 1'b0;
        snoop_data_next     = 128'd0;
        snoop_found         = 1'b0;
        snoop_index         = 2'd0;
        for (i = 0; i < ENTRIES; i = i + 1) begin
            if (!snoop_found && enable && snoop_valid &&
                (mesi_state[i] != MESI_I) &&
                (block_addr[i] == snoop_addr[31:4])) begin
                snoop_hit_next      = 1'b1;
                snoop_modified_next = (mesi_state[i] == MESI_M);
                snoop_data_next     = data_block[i];
                snoop_index         = i[1:0];
                snoop_found         = 1'b1;
            end
        end
        snoop_hit      = snoop_hit_next;
        snoop_modified = snoop_modified_next;
        snoop_data     = snoop_data_next;
    end

    always @(posedge clk) begin
        if (reset) begin
            fifo_pointer <= 2'd0;
            for (i = 0; i < ENTRIES; i = i + 1) begin
                block_addr[i] <= 28'd0;
                data_block[i] <= 128'd0;
                mesi_state[i] <= MESI_I;
            end
        end else begin
            // Snoop state changes have priority over local management. The L1
            // never starts a local victim operation while snoop_valid is high.
            if (enable && snoop_valid && snoop_hit) begin
                case (snoop_cmd)
                    BUS_RD: begin
                        if ((mesi_state[snoop_index] == MESI_M) ||
                            (mesi_state[snoop_index] == MESI_E)) begin
                            mesi_state[snoop_index] <= MESI_S;
                        end
                    end
                    BUS_RDX, BUS_UPGR: begin
                        mesi_state[snoop_index] <= MESI_I;
                    end
                    default: begin
                    end
                endcase
            end else if (enable) begin
                if (manager_write) begin
                    block_addr[manager_index] <= manager_block_addr;
                    data_block[manager_index] <= manager_data;
                    mesi_state[manager_index] <= manager_state;
                end else if (manager_invalidate) begin
                    mesi_state[manager_invalidate_index] <= MESI_I;
                end

                if (manager_advance_fifo) begin
                    fifo_pointer <= fifo_pointer + 2'd1;
                end
            end
        end
    end
endmodule

`default_nettype wire
