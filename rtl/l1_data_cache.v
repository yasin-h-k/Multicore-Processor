`timescale 1ns/1ps
`default_nettype none

module l1_data_cache #(
    parameter integer CACHE_ID = 0,
    parameter integer ENABLE_VICTIM_CACHE = 1
) (
    input  wire         clk,
    input  wire         reset,

    input  wire         cpu_req,
    input  wire         cpu_we,
    input  wire [31:0]  cpu_addr,
    input  wire [31:0]  cpu_wdata,
    output reg [31:0]   cpu_rdata,
    output reg          cpu_ready,
    output reg          cpu_stall,

    output reg          bus_req,
    output reg [1:0]    bus_cmd,
    output reg [31:0]   bus_addr,
    output reg [127:0]  bus_wdata,
    input  wire         bus_done,
    input  wire [127:0] bus_rdata,
    input  wire         bus_shared,

    input  wire         snoop_valid,
    input  wire [1:0]   snoop_cmd,
    input  wire [31:0]  snoop_addr,
    output reg          snoop_hit,
    output reg          snoop_modified,
    output reg [127:0]  snoop_data,

    output reg          debug_hit_pulse,
    output reg          debug_miss_pulse,
    output reg          debug_victim_hit_pulse,
    output reg [1:0]    debug_cpu_index,
    output reg [25:0]   debug_cpu_tag,
    output reg [3:0]    debug_fsm_state,
    output wire [1:0]   debug_victim_fifo
);
    localparam [1:0] MESI_I = 2'b00;
    localparam [1:0] MESI_S = 2'b01;
    localparam [1:0] MESI_E = 2'b10;
    localparam [1:0] MESI_M = 2'b11;

    localparam [1:0] BUS_RD   = 2'b00;
    localparam [1:0] BUS_RDX  = 2'b01;
    localparam [1:0] BUS_UPGR = 2'b10;
    localparam [1:0] BUS_WB   = 2'b11;

    localparam [3:0] C_IDLE       = 4'd0;
    localparam [3:0] C_L1_WB      = 4'd1;
    localparam [3:0] C_MISS       = 4'd2;
    localparam [3:0] C_UPGR       = 4'd3;
    localparam [3:0] C_RESP       = 4'd4;
    localparam [3:0] C_VC_WB      = 4'd5;
    localparam [3:0] C_VC_INSERT  = 4'd6;
    localparam [3:0] C_VC_SWAP    = 4'd7;

    // Four-line, direct-mapped L1.
    reg [25:0]  tags       [0:3];
    reg [127:0] data_lines [0:3];
    reg [1:0]   mesi_state [0:3];

    reg [3:0] state;

    reg [31:0] req_addr;
    reg        req_we;
    reg [31:0] req_wdata;
    reg [1:0]  req_index;
    reg [25:0] req_tag;
    reg [1:0]  req_word;

    // Pending L1 block that will be moved into the victim cache.
    reg         pending_l1_valid;
    reg [27:0]  pending_l1_block_addr;
    reg [127:0] pending_l1_data;
    reg [1:0]   pending_l1_state;
    reg [1:0]   pending_vc_index;

    // Latched block obtained from a victim-cache hit.
    reg [1:0]   pending_vc_hit_index;
    reg [127:0] pending_vc_hit_data;
    reg [1:0]   pending_vc_hit_state;

    reg [31:0]  legacy_victim_addr;
    reg [127:0] legacy_victim_data;
    reg [31:0]  response_rdata;

    wire [1:0]  cpu_index_now;
    wire [25:0] cpu_tag_now;
    wire [1:0]  cpu_word_now;
    wire        cpu_hit_now;
    wire [1:0]  snoop_index_now;
    wire [25:0] snoop_tag_now;
    wire        l1_snoop_hit;
    wire        l1_snoop_modified;
    wire [127:0] l1_snoop_data;

    // Victim-cache lookup/replacement/snoop signals.
    wire        vc_lookup_hit;
    wire [1:0]  vc_lookup_index;
    wire [1:0]  vc_lookup_state;
    wire [127:0] vc_lookup_data;
    wire [1:0]  vc_replacement_index;
    wire        vc_replacement_valid;
    wire [27:0] vc_replacement_block_addr;
    wire [1:0]  vc_replacement_state;
    wire [127:0] vc_replacement_data;
    wire        vc_snoop_hit;
    wire        vc_snoop_modified;
    wire [127:0] vc_snoop_data;

    reg         vc_manager_write;
    reg [1:0]   vc_manager_index;
    reg [27:0]  vc_manager_block_addr;
    reg [127:0] vc_manager_data;
    reg [1:0]   vc_manager_state;
    reg         vc_manager_invalidate;
    reg [1:0]   vc_manager_invalidate_index;
    reg         vc_manager_advance_fifo;

    integer i;

    assign cpu_index_now   = cpu_addr[5:4];
    assign cpu_tag_now     = cpu_addr[31:6];
    assign cpu_word_now    = cpu_addr[3:2];
    assign cpu_hit_now     = (mesi_state[cpu_index_now] != MESI_I) &&
                             (tags[cpu_index_now] == cpu_tag_now);
    assign snoop_index_now = snoop_addr[5:4];
    assign snoop_tag_now   = snoop_addr[31:6];

    assign l1_snoop_hit = snoop_valid &&
                          (mesi_state[snoop_index_now] != MESI_I) &&
                          (tags[snoop_index_now] == snoop_tag_now);
    assign l1_snoop_modified = l1_snoop_hit &&
                               (mesi_state[snoop_index_now] == MESI_M);
    assign l1_snoop_data = l1_snoop_hit ? data_lines[snoop_index_now] : 128'd0;

    function [31:0] block_read_word;
        input [127:0] block;
        input [1:0] word_select;
        begin
            case (word_select)
                2'd0: block_read_word = block[31:0];
                2'd1: block_read_word = block[63:32];
                2'd2: block_read_word = block[95:64];
                default: block_read_word = block[127:96];
            endcase
        end
    endfunction

    function [127:0] block_write_word;
        input [127:0] block;
        input [1:0] word_select;
        input [31:0] word_data;
        begin
            block_write_word = block;
            case (word_select)
                2'd0: block_write_word[31:0]   = word_data;
                2'd1: block_write_word[63:32]  = word_data;
                2'd2: block_write_word[95:64]  = word_data;
                2'd3: block_write_word[127:96] = word_data;
            endcase
        end
    endfunction

    victim_cache #(.ENTRIES(4)) victim (
        .clk(clk),
        .reset(reset),
        .enable(ENABLE_VICTIM_CACHE != 0),
        .lookup_addr(cpu_addr),
        .lookup_hit(vc_lookup_hit),
        .lookup_index(vc_lookup_index),
        .lookup_state(vc_lookup_state),
        .lookup_data(vc_lookup_data),
        .replacement_index(vc_replacement_index),
        .replacement_valid(vc_replacement_valid),
        .replacement_block_addr(vc_replacement_block_addr),
        .replacement_state(vc_replacement_state),
        .replacement_data(vc_replacement_data),
        .manager_write(vc_manager_write),
        .manager_index(vc_manager_index),
        .manager_block_addr(vc_manager_block_addr),
        .manager_data(vc_manager_data),
        .manager_state(vc_manager_state),
        .manager_invalidate(vc_manager_invalidate),
        .manager_invalidate_index(vc_manager_invalidate_index),
        .manager_advance_fifo(vc_manager_advance_fifo),
        .snoop_valid(snoop_valid),
        .snoop_cmd(snoop_cmd),
        .snoop_addr(snoop_addr),
        .snoop_hit(vc_snoop_hit),
        .snoop_modified(vc_snoop_modified),
        .snoop_data(vc_snoop_data),
        .debug_fifo_pointer(debug_victim_fifo)
    );

    // Bus, CPU-response, and victim-management outputs.
    always @* begin
        cpu_rdata       = response_rdata;
        cpu_ready       = (state == C_RESP);
        cpu_stall       = cpu_req && !cpu_ready;
        debug_cpu_index = cpu_addr[5:4];
        debug_cpu_tag   = cpu_addr[31:6];
        debug_fsm_state = state;

        bus_req   = 1'b0;
        bus_cmd   = BUS_RD;
        bus_addr  = 32'd0;
        bus_wdata = 128'd0;

        vc_manager_write            = 1'b0;
        vc_manager_index            = pending_vc_index;
        vc_manager_block_addr       = pending_l1_block_addr;
        vc_manager_data             = pending_l1_data;
        vc_manager_state            = pending_l1_state;
        vc_manager_invalidate       = 1'b0;
        vc_manager_invalidate_index = pending_vc_hit_index;
        vc_manager_advance_fifo     = 1'b0;

        case (state)
            C_IDLE: begin
                // A victim hit is swapped atomically at the same edge on
                // which it is detected. No intermediate state exposes two
                // copies or allows a snoop to race with the swap.
                if (cpu_req && !snoop_valid && !cpu_hit_now &&
                    (ENABLE_VICTIM_CACHE != 0) && vc_lookup_hit) begin
                    if (mesi_state[cpu_index_now] != MESI_I) begin
                        vc_manager_write      = 1'b1;
                        vc_manager_index      = vc_lookup_index;
                        vc_manager_block_addr = {tags[cpu_index_now], cpu_index_now};
                        vc_manager_data       = data_lines[cpu_index_now];
                        vc_manager_state      = mesi_state[cpu_index_now];
                    end else begin
                        vc_manager_invalidate       = 1'b1;
                        vc_manager_invalidate_index = vc_lookup_index;
                    end
                end
            end
            C_L1_WB: begin
                bus_req   = 1'b1;
                bus_cmd   = BUS_WB;
                bus_addr  = legacy_victim_addr;
                bus_wdata = legacy_victim_data;
            end
            C_VC_WB: begin
                bus_req   = 1'b1;
                bus_cmd   = BUS_WB;
                bus_addr  = {vc_replacement_block_addr, 4'b0000};
                bus_wdata = vc_replacement_data;
            end
            C_VC_INSERT: begin
                if (!snoop_valid) begin
                    vc_manager_write        = pending_l1_valid;
                    vc_manager_index        = pending_vc_index;
                    vc_manager_advance_fifo = pending_l1_valid;
                end
            end
            C_MISS: begin
                bus_req   = 1'b1;
                bus_cmd   = req_we ? BUS_RDX : BUS_RD;
                bus_addr  = {req_addr[31:4], 4'b0000};
            end
            C_UPGR: begin
                bus_req   = 1'b1;
                bus_cmd   = BUS_UPGR;
                bus_addr  = {req_addr[31:4], 4'b0000};
            end
            default: begin
            end
        endcase
    end

    // L1 and victim-cache snoop responses are merged. A duplicate should not
    // exist, but L1 is given priority as the architecturally closer level.
    always @* begin
        if (l1_snoop_hit) begin
            snoop_hit      = 1'b1;
            snoop_modified = l1_snoop_modified;
            snoop_data     = l1_snoop_data;
        end else if (vc_snoop_hit) begin
            snoop_hit      = 1'b1;
            snoop_modified = vc_snoop_modified;
            snoop_data     = vc_snoop_data;
        end else begin
            snoop_hit      = 1'b0;
            snoop_modified = 1'b0;
            snoop_data     = 128'd0;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state                    <= C_IDLE;
            req_addr                 <= 32'd0;
            req_we                   <= 1'b0;
            req_wdata                <= 32'd0;
            req_index                <= 2'd0;
            req_tag                  <= 26'd0;
            req_word                 <= 2'd0;
            pending_l1_valid         <= 1'b0;
            pending_l1_block_addr    <= 28'd0;
            pending_l1_data          <= 128'd0;
            pending_l1_state         <= MESI_I;
            pending_vc_index         <= 2'd0;
            pending_vc_hit_index     <= 2'd0;
            pending_vc_hit_data      <= 128'd0;
            pending_vc_hit_state     <= MESI_I;
            legacy_victim_addr       <= 32'd0;
            legacy_victim_data       <= 128'd0;
            response_rdata           <= 32'd0;
            debug_hit_pulse          <= 1'b0;
            debug_miss_pulse         <= 1'b0;
            debug_victim_hit_pulse   <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                tags[i]       <= 26'd0;
                data_lines[i] <= 128'd0;
                mesi_state[i] <= MESI_I;
            end
        end else begin
            debug_hit_pulse        <= 1'b0;
            debug_miss_pulse       <= 1'b0;
            debug_victim_hit_pulse <= 1'b0;

            // Only the L1 copy is updated here; victim-cache snoop transitions
            // are performed inside victim_cache.v at the same edge.
            if (snoop_valid && l1_snoop_hit) begin
                case (snoop_cmd)
                    BUS_RD: begin
                        if ((mesi_state[snoop_index_now] == MESI_M) ||
                            (mesi_state[snoop_index_now] == MESI_E)) begin
                            mesi_state[snoop_index_now] <= MESI_S;
                        end
                    end
                    BUS_RDX, BUS_UPGR: begin
                        mesi_state[snoop_index_now] <= MESI_I;
                    end
                    default: begin
                    end
                endcase

                // Before C_VC_INSERT the pending block is still the same L1
                // line. Mirror snoop state changes into the pending metadata.
                if (pending_l1_valid &&
                    (pending_l1_block_addr == snoop_addr[31:4])) begin
                    case (snoop_cmd)
                        BUS_RD: begin
                            if ((pending_l1_state == MESI_M) ||
                                (pending_l1_state == MESI_E)) begin
                                pending_l1_state <= MESI_S;
                            end
                        end
                        BUS_RDX, BUS_UPGR: begin
                            pending_l1_valid <= 1'b0;
                            pending_l1_state <= MESI_I;
                        end
                        default: begin
                        end
                    endcase
                end
            end

            case (state)
                C_IDLE: begin
                    if (cpu_req && !snoop_valid) begin
                        if (cpu_hit_now) begin
                            debug_hit_pulse <= 1'b1;
                            if (!cpu_we) begin
                                response_rdata <= block_read_word(
                                    data_lines[cpu_index_now], cpu_word_now);
                                state <= C_RESP;
                            end else begin
                                case (mesi_state[cpu_index_now])
                                    MESI_M: begin
                                        data_lines[cpu_index_now] <= block_write_word(
                                            data_lines[cpu_index_now], cpu_word_now,
                                            cpu_wdata);
                                        response_rdata <= cpu_wdata;
                                        state <= C_RESP;
                                    end
                                    MESI_E: begin
                                        data_lines[cpu_index_now] <= block_write_word(
                                            data_lines[cpu_index_now], cpu_word_now,
                                            cpu_wdata);
                                        mesi_state[cpu_index_now] <= MESI_M;
                                        response_rdata <= cpu_wdata;
                                        state <= C_RESP;
                                    end
                                    MESI_S: begin
                                        req_addr  <= cpu_addr;
                                        req_we    <= 1'b1;
                                        req_wdata <= cpu_wdata;
                                        req_index <= cpu_index_now;
                                        req_tag   <= cpu_tag_now;
                                        req_word  <= cpu_word_now;
                                        state     <= C_UPGR;
                                    end
                                    default: state <= C_IDLE;
                                endcase
                            end
                        end else if ((ENABLE_VICTIM_CACHE != 0) && vc_lookup_hit) begin
                            // Atomically swap the direct-mapped L1 line with
                            // the fully-associative victim entry. The victim
                            // module samples its manager command at this edge.
                            debug_victim_hit_pulse <= 1'b1;
                            req_addr  <= cpu_addr;
                            req_we    <= cpu_we;
                            req_wdata <= cpu_wdata;
                            req_index <= cpu_index_now;
                            req_tag   <= cpu_tag_now;
                            req_word  <= cpu_word_now;
                            tags[cpu_index_now] <= cpu_tag_now;

                            if (cpu_we && (vc_lookup_state != MESI_S)) begin
                                data_lines[cpu_index_now] <= block_write_word(
                                    vc_lookup_data, cpu_word_now, cpu_wdata);
                                mesi_state[cpu_index_now] <= MESI_M;
                                response_rdata <= cpu_wdata;
                                state <= C_RESP;
                            end else begin
                                data_lines[cpu_index_now] <= vc_lookup_data;
                                mesi_state[cpu_index_now] <= vc_lookup_state;
                                if (cpu_we) begin
                                    // Shared victim data still needs BusUpgr.
                                    state <= C_UPGR;
                                end else begin
                                    response_rdata <= block_read_word(
                                        vc_lookup_data, cpu_word_now);
                                    state <= C_RESP;
                                end
                            end
                        end else begin
                            debug_miss_pulse <= 1'b1;
                            req_addr  <= cpu_addr;
                            req_we    <= cpu_we;
                            req_wdata <= cpu_wdata;
                            req_index <= cpu_index_now;
                            req_tag   <= cpu_tag_now;
                            req_word  <= cpu_word_now;

                            if (ENABLE_VICTIM_CACHE != 0) begin
                                pending_l1_valid <=
                                    (mesi_state[cpu_index_now] != MESI_I);
                                pending_l1_block_addr <=
                                    {tags[cpu_index_now], cpu_index_now};
                                pending_l1_data  <= data_lines[cpu_index_now];
                                pending_l1_state <= mesi_state[cpu_index_now];
                                pending_vc_index <= vc_replacement_index;

                                if (mesi_state[cpu_index_now] == MESI_I) begin
                                    state <= C_MISS;
                                end else if (vc_replacement_valid &&
                                             (vc_replacement_state == MESI_M)) begin
                                    state <= C_VC_WB;
                                end else begin
                                    state <= C_VC_INSERT;
                                end
                            end else if (mesi_state[cpu_index_now] == MESI_M) begin
                                legacy_victim_addr <= {tags[cpu_index_now],
                                                       cpu_index_now, 4'b0000};
                                legacy_victim_data <= data_lines[cpu_index_now];
                                state <= C_L1_WB;
                            end else begin
                                state <= C_MISS;
                            end
                        end
                    end
                end

                C_VC_WB: begin
                    if (bus_done) begin
                        state <= C_VC_INSERT;
                    end
                end

                C_VC_INSERT: begin
                    // A snoop has priority; wait until the hierarchy is quiet
                    // before moving the pending L1 block into victim storage.
                    if (!snoop_valid) begin
                        if (pending_l1_valid) begin
                            mesi_state[req_index] <= MESI_I;
                        end
                        state <= C_MISS;
                    end
                end

                C_L1_WB: begin
                    if (bus_done) begin
                        mesi_state[req_index] <= MESI_I;
                        state <= C_MISS;
                    end
                end

                C_MISS: begin
                    if (bus_done) begin
                        tags[req_index] <= req_tag;
                        if (req_we) begin
                            data_lines[req_index] <= block_write_word(
                                bus_rdata, req_word, req_wdata);
                            mesi_state[req_index] <= MESI_M;
                            response_rdata <= req_wdata;
                        end else begin
                            data_lines[req_index] <= bus_rdata;
                            mesi_state[req_index] <= bus_shared ? MESI_S : MESI_E;
                            response_rdata <= block_read_word(bus_rdata, req_word);
                        end
                        state <= C_RESP;
                    end
                end

                C_UPGR: begin
                    if (bus_done) begin
                        data_lines[req_index] <= block_write_word(
                            data_lines[req_index], req_word, req_wdata);
                        mesi_state[req_index] <= MESI_M;
                        response_rdata <= req_wdata;
                        state <= C_RESP;
                    end
                end

                C_RESP: begin
                    state <= C_IDLE;
                end

                default: state <= C_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
