`timescale 1ns/1ps
`default_nettype none

module tb_cache_mesi;
    localparam [1:0] MESI_I = 2'b00;
    localparam [1:0] MESI_S = 2'b01;
    localparam [1:0] MESI_E = 2'b10;
    localparam [1:0] MESI_M = 2'b11;

    reg clk;
    reg reset;
    integer errors;

    reg c0_cpu_req, c0_cpu_we;
    reg [31:0] c0_cpu_addr, c0_cpu_wdata;
    wire c0_cpu_ready, c0_cpu_stall;
    wire [31:0] c0_cpu_rdata;
    reg c1_cpu_req, c1_cpu_we;
    reg [31:0] c1_cpu_addr, c1_cpu_wdata;
    wire c1_cpu_ready, c1_cpu_stall;
    wire [31:0] c1_cpu_rdata;

    wire c0_bus_req, c0_bus_done, c0_bus_shared;
    wire [1:0] c0_bus_cmd;
    wire [31:0] c0_bus_addr;
    wire [127:0] c0_bus_wdata, c0_bus_rdata;
    wire c1_bus_req, c1_bus_done, c1_bus_shared;
    wire [1:0] c1_bus_cmd;
    wire [31:0] c1_bus_addr;
    wire [127:0] c1_bus_wdata, c1_bus_rdata;

    wire snoop0_valid, snoop0_hit, snoop0_modified;
    wire [1:0] snoop0_cmd;
    wire [31:0] snoop0_addr;
    wire [127:0] snoop0_data;
    wire snoop1_valid, snoop1_hit, snoop1_modified;
    wire [1:0] snoop1_cmd;
    wire [31:0] snoop1_addr;
    wire [127:0] snoop1_data;

    wire mem_req, mem_we, mem_ready;
    wire [31:0] mem_addr;
    wire [127:0] mem_wdata, mem_rdata;
    wire mem_write_pulse, mem_read_pulse;

    wire grant0_pulse, grant1_pulse;
    wire [2:0] bus_state;
    wire bus_owner;
    wire [1:0] bus_cmd_debug;

    wire cache0_hit, cache0_miss;
    wire [1:0] cache0_index;
    wire [25:0] cache0_tag;
    wire [3:0] cache0_state;
    wire cache0_victim_hit;
    wire [1:0] cache0_victim_fifo;
    wire cache1_hit, cache1_miss;
    wire [1:0] cache1_index;
    wire [25:0] cache1_tag;
    wire [3:0] cache1_state;
    wire cache1_victim_hit;
    wire [1:0] cache1_victim_fifo;

    l1_data_cache #(.CACHE_ID(0), .ENABLE_VICTIM_CACHE(1)) cache0 (
        .clk(clk), .reset(reset),
        .cpu_req(c0_cpu_req), .cpu_we(c0_cpu_we), .cpu_addr(c0_cpu_addr),
        .cpu_wdata(c0_cpu_wdata), .cpu_rdata(c0_cpu_rdata),
        .cpu_ready(c0_cpu_ready), .cpu_stall(c0_cpu_stall),
        .bus_req(c0_bus_req), .bus_cmd(c0_bus_cmd), .bus_addr(c0_bus_addr),
        .bus_wdata(c0_bus_wdata), .bus_done(c0_bus_done),
        .bus_rdata(c0_bus_rdata), .bus_shared(c0_bus_shared),
        .snoop_valid(snoop0_valid), .snoop_cmd(snoop0_cmd),
        .snoop_addr(snoop0_addr), .snoop_hit(snoop0_hit),
        .snoop_modified(snoop0_modified), .snoop_data(snoop0_data),
        .debug_hit_pulse(cache0_hit), .debug_miss_pulse(cache0_miss),
        .debug_victim_hit_pulse(cache0_victim_hit),
        .debug_cpu_index(cache0_index), .debug_cpu_tag(cache0_tag),
        .debug_fsm_state(cache0_state),
        .debug_victim_fifo(cache0_victim_fifo)
    );

    l1_data_cache #(.CACHE_ID(1), .ENABLE_VICTIM_CACHE(1)) cache1 (
        .clk(clk), .reset(reset),
        .cpu_req(c1_cpu_req), .cpu_we(c1_cpu_we), .cpu_addr(c1_cpu_addr),
        .cpu_wdata(c1_cpu_wdata), .cpu_rdata(c1_cpu_rdata),
        .cpu_ready(c1_cpu_ready), .cpu_stall(c1_cpu_stall),
        .bus_req(c1_bus_req), .bus_cmd(c1_bus_cmd), .bus_addr(c1_bus_addr),
        .bus_wdata(c1_bus_wdata), .bus_done(c1_bus_done),
        .bus_rdata(c1_bus_rdata), .bus_shared(c1_bus_shared),
        .snoop_valid(snoop1_valid), .snoop_cmd(snoop1_cmd),
        .snoop_addr(snoop1_addr), .snoop_hit(snoop1_hit),
        .snoop_modified(snoop1_modified), .snoop_data(snoop1_data),
        .debug_hit_pulse(cache1_hit), .debug_miss_pulse(cache1_miss),
        .debug_victim_hit_pulse(cache1_victim_hit),
        .debug_cpu_index(cache1_index), .debug_cpu_tag(cache1_tag),
        .debug_fsm_state(cache1_state),
        .debug_victim_fifo(cache1_victim_fifo)
    );

    bus_arbiter arbiter (
        .clk(clk), .reset(reset),
        .c0_req(c0_bus_req), .c0_cmd(c0_bus_cmd), .c0_addr(c0_bus_addr),
        .c0_wdata(c0_bus_wdata), .c0_done(c0_bus_done),
        .c0_rdata(c0_bus_rdata), .c0_shared(c0_bus_shared),
        .c0_grant_pulse(grant0_pulse),
        .c1_req(c1_bus_req), .c1_cmd(c1_bus_cmd), .c1_addr(c1_bus_addr),
        .c1_wdata(c1_bus_wdata), .c1_done(c1_bus_done),
        .c1_rdata(c1_bus_rdata), .c1_shared(c1_bus_shared),
        .c1_grant_pulse(grant1_pulse),
        .snoop0_valid(snoop0_valid), .snoop0_cmd(snoop0_cmd),
        .snoop0_addr(snoop0_addr), .snoop0_hit(snoop0_hit),
        .snoop0_modified(snoop0_modified), .snoop0_data(snoop0_data),
        .snoop1_valid(snoop1_valid), .snoop1_cmd(snoop1_cmd),
        .snoop1_addr(snoop1_addr), .snoop1_hit(snoop1_hit),
        .snoop1_modified(snoop1_modified), .snoop1_data(snoop1_data),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready),
        .debug_state(bus_state), .debug_owner(bus_owner), .debug_cmd(bus_cmd_debug)
    );

    shared_main_memory #(
        .BLOCKS(256), .LATENCY(3), .INIT_FILE("mem/data_memory.mem")
    ) memory (
        .clk(clk), .reset(reset), .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_ready(mem_ready), .debug_write_pulse(mem_write_pulse),
        .debug_read_pulse(mem_read_pulse)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*128-1:0] message;
        begin
            if (!condition) begin
                errors = errors + 1;
                $display("[FAIL] %0s", message);
            end else begin
                $display("[ OK ] %0s", message);
            end
        end
    endtask

    task cpu0_read;
        input [31:0] address;
        output [31:0] data;
        integer timeout;
        begin
            @(negedge clk);
            c0_cpu_addr  = address;
            c0_cpu_wdata = 32'd0;
            c0_cpu_we    = 1'b0;
            c0_cpu_req   = 1'b1;
            timeout = 0;
            while (!c0_cpu_ready) begin
                @(negedge clk);
                timeout = timeout + 1;
                if (timeout > 200) begin
                    $display("[FATAL] cpu0_read timeout at %h", address);
                    $finish;
                end
            end
            data = c0_cpu_rdata;
            c0_cpu_req = 1'b0;
            @(negedge clk);
        end
    endtask

    task cpu1_read;
        input [31:0] address;
        output [31:0] data;
        integer timeout;
        begin
            @(negedge clk);
            c1_cpu_addr  = address;
            c1_cpu_wdata = 32'd0;
            c1_cpu_we    = 1'b0;
            c1_cpu_req   = 1'b1;
            timeout = 0;
            while (!c1_cpu_ready) begin
                @(negedge clk);
                timeout = timeout + 1;
                if (timeout > 200) begin
                    $display("[FATAL] cpu1_read timeout at %h", address);
                    $finish;
                end
            end
            data = c1_cpu_rdata;
            c1_cpu_req = 1'b0;
            @(negedge clk);
        end
    endtask

    task cpu0_write;
        input [31:0] address;
        input [31:0] data;
        integer timeout;
        begin
            @(negedge clk);
            c0_cpu_addr  = address;
            c0_cpu_wdata = data;
            c0_cpu_we    = 1'b1;
            c0_cpu_req   = 1'b1;
            timeout = 0;
            while (!c0_cpu_ready) begin
                @(negedge clk);
                timeout = timeout + 1;
                if (timeout > 200) begin
                    $display("[FATAL] cpu0_write timeout at %h", address);
                    $finish;
                end
            end
            c0_cpu_req = 1'b0;
            c0_cpu_we  = 1'b0;
            @(negedge clk);
        end
    endtask

    task cpu1_write;
        input [31:0] address;
        input [31:0] data;
        integer timeout;
        begin
            @(negedge clk);
            c1_cpu_addr  = address;
            c1_cpu_wdata = data;
            c1_cpu_we    = 1'b1;
            c1_cpu_req   = 1'b1;
            timeout = 0;
            while (!c1_cpu_ready) begin
                @(negedge clk);
                timeout = timeout + 1;
                if (timeout > 200) begin
                    $display("[FATAL] cpu1_write timeout at %h", address);
                    $finish;
                end
            end
            c1_cpu_req = 1'b0;
            c1_cpu_we  = 1'b0;
            @(negedge clk);
        end
    endtask

    task simultaneous_reads;
        input [31:0] address0;
        input [31:0] address1;
        input integer expected_first;
        reg [31:0] data0;
        reg [31:0] data1;
        integer first_grant;
        begin
            first_grant = -1;
            fork
                cpu0_read(address0, data0);
                cpu1_read(address1, data1);
                begin
                    while (first_grant == -1) begin
                        @(negedge clk);
                        if (grant0_pulse) first_grant = 0;
                        else if (grant1_pulse) first_grant = 1;
                    end
                end
            join
            if (first_grant != expected_first) begin
                errors = errors + 1;
                $display("[FAIL] round-robin first grant expected core %0d, got core %0d",
                         expected_first, first_grant);
            end else begin
                $display("[ OK ] round-robin first grant is core %0d", expected_first);
            end
            check(data0 == memory.mem[address0[31:4]][31:0],
                  "simultaneous core 0 read returned correct data");
            check(data1 == memory.mem[address1[31:4]][31:0],
                  "simultaneous core 1 read returned correct data");
        end
    endtask

    reg [31:0] rdata;

    initial begin
        $dumpfile("build/cache_mesi.vcd");
        $dumpvars(0, tb_cache_mesi);

        clk = 0;
        reset = 1;
        errors = 0;
        c0_cpu_req = 0;
        c0_cpu_we = 0;
        c0_cpu_addr = 32'd0;
        c0_cpu_wdata = 32'd0;
        c1_cpu_req = 1'b0;
        c1_cpu_we = 1'b0;
        c1_cpu_addr = 32'd0;
        c1_cpu_wdata = 32'd0;

        repeat (4) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        $display("\n--- Scenario 1: shared read by both cores ---");
        cpu0_read(32'h0000_0100, rdata);
        check(rdata == 32'h1111_1111, "core 0 first read value");
        check(cache0.mesi_state[0] == MESI_E, "core 0 first reader obtains E");
        cpu1_read(32'h0000_0100, rdata);
        check(rdata == 32'h1111_1111, "core 1 shared read value");
        check(cache0.mesi_state[0] == MESI_S, "core 0 downgraded E to S");
        check(cache1.mesi_state[0] == MESI_S, "core 1 receives S");

        $display("\n--- Scenario 2: one core writes shared data ---");
        cpu0_write(32'h0000_0100, 32'h2222_2222);
        check(cache0.mesi_state[0] == MESI_M, "core 0 S-to-M upgrade completed");
        check(cache1.mesi_state[0] == MESI_I, "core 1 shared copy invalidated");
        cpu1_read(32'h0000_0100, rdata);
        check(rdata == 32'h2222_2222, "core 1 receives updated modified data");
        check(cache0.mesi_state[0] == MESI_S, "modified owner downgraded to S");
        check(cache1.mesi_state[0] == MESI_S, "requester receives S");
        check(memory.mem[16][31:0] == 32'h2222_2222,
              "modified intervention updates main memory");

        $display("\n--- Scenario 3: L1 eviction into the Victim Cache ---");
        cpu0_write(32'h0000_0100, 32'h3333_3333);
        check(cache0.mesi_state[0] == MESI_M, "core 0 owns modified A");
        cpu0_read(32'h0000_0140, rdata);
        check(rdata == 32'hbbbb_0001, "conflicting block B installed in L1");
        check(cache0.victim.mesi_state[0] == MESI_M,
              "modified A moved to victim cache without immediate write-back");
        check(cache0.victim.block_addr[0] == (32'h0000_0100 >> 4),
              "victim entry stores full block address A");
        check(cache0.victim.data_block[0][31:0] == 32'h3333_3333,
              "victim entry preserves modified A data");
        check(memory.mem[16][31:0] == 32'h2222_2222,
              "memory remains unchanged while M block is protected in victim cache");
        check(cache0.mesi_state[0] == MESI_E, "new clean block installed E");

        cpu0_read(32'h0000_0100, rdata);
        check(rdata == 32'h3333_3333, "victim-cache hit returns modified A");
        check(cache0.mesi_state[0] == MESI_M,
              "victim hit restores A to L1 with its MESI state");
        check(cache0.victim.block_addr[0] == (32'h0000_0140 >> 4),
              "victim hit swaps displaced L1 block B into the hit entry");
        check(cache0.victim.mesi_state[0] == MESI_E,
              "swapped B preserves its clean Exclusive state");

        // Reset both L1 caches, both victim caches, and the bus arbiter.
        // This gives both cores identical empty cache states before
        // testing simultaneous bus arbitration.
        @(negedge clk);

        reset        = 1'b1;

        c0_cpu_req   = 1'b0;
        c0_cpu_we    = 1'b0;
        c0_cpu_addr  = 32'd0;
        c0_cpu_wdata = 32'd0;

        c1_cpu_req   = 1'b0;
        c1_cpu_we    = 1'b0;
        c1_cpu_addr  = 32'd0;
        c1_cpu_wdata = 32'd0;

        repeat (3) @(posedge clk);

        @(negedge clk);
        reset = 1'b0;

        repeat (2) @(posedge clk);

        $display("\n--- Scenario 4: simultaneous bus requests ---");
        simultaneous_reads(32'h0000_0200, 32'h0000_0210, 0);
        simultaneous_reads(32'h0000_0220, 32'h0000_0230, 1);

        $display("\n--- Scenario 5: read block held Modified by peer ---");
        cpu0_write(32'h0000_0240, 32'haaaa_0001);
        check(cache0.mesi_state[0] == MESI_M, "core 0 holds E block in M after write miss");
        cpu1_read(32'h0000_0240, rdata);
        check(rdata == 32'haaaa_0001, "peer read receives latest M data");
        check(cache0.mesi_state[0] == MESI_S, "M owner becomes S on BusRd");
        check(cache1.mesi_state[0] == MESI_S, "reader becomes S");

        $display("\n--- Scenario 6: write ownership against E/S/M ---");
        cpu0_read(32'h0000_0250, rdata);
        check(cache0.mesi_state[1] == MESI_E, "core 0 holds F in E");
        cpu1_write(32'h0000_0250, 32'hf0f0_0001);
        check(cache0.mesi_state[1] == MESI_I, "core 0 E invalidated by BusRdX");
        check(cache1.mesi_state[1] == MESI_M, "core 1 write miss ends M");
        check(cache1.data_lines[1][31:0] == 32'hf0f0_0001,
              "core 1 stores requested word in M line");

        cpu0_write(32'h0000_0260, 32'haaaa_aaaa);
        check(cache0.mesi_state[2] == MESI_M, "core 0 holds G in M");
        cpu1_write(32'h0000_0260, 32'hbbbb_bbbb);
        check(cache0.mesi_state[2] == MESI_I, "core 0 M invalidated by peer write");
        check(cache1.mesi_state[2] == MESI_M, "core 1 obtains M after peer M intervention");
        cpu0_read(32'h0000_0260, rdata);
        check(rdata == 32'hbbbb_bbbb, "later reader receives newest core 1 value");
        check(cache0.mesi_state[2] == MESI_S, "core 0 becomes S after read");
        check(cache1.mesi_state[2] == MESI_S, "core 1 M downgrades to S");
        check(memory.mem[38][31:0] == 32'hbbbb_bbbb,
              "memory receives newest modified value on intervention");


        $display("\n--- Scenario 7: victim snoop and FIFO replacement ---");
        // Reset the private hierarchy for a deterministic FIFO pointer.
        @(negedge clk);
        reset = 1'b1;
        c0_cpu_req = 1'b0;
        c1_cpu_req = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        // Put a Modified block in victim slot 0, then make the peer read it.
        cpu0_write(32'h0000_0300, 32'hdead_beef);
        cpu0_read(32'h0000_0340, rdata);
        check(cache0.victim.mesi_state[0] == MESI_M,
              "modified 0x300 block resides in victim slot 0");
        cpu1_read(32'h0000_0300, rdata);
        check(rdata == 32'hdead_beef,
              "peer BusRd obtains newest data directly from victim cache");
        check(cache0.victim.mesi_state[0] == MESI_S,
              "victim M entry downgrades to S after peer BusRd");
        check(cache1.mesi_state[0] == MESI_S,
              "peer requester installs shared block from victim response");

        // Reset again and fill all four FIFO victim entries. The fifth L1
        // eviction replaces slot 0, whose M block must first be written back.
        @(negedge clk);
        reset = 1'b1;
        c0_cpu_req = 1'b0;
        c1_cpu_req = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        cpu0_write(32'h0000_0300, 32'hcafe_babe); // A becomes M in L1.
        cpu0_read (32'h0000_0340, rdata);         // A -> victim slot 0.
        cpu0_read (32'h0000_0380, rdata);         // B -> victim slot 1.
        cpu0_read (32'h0000_03c0, rdata);         // C -> victim slot 2.
        cpu0_read (32'h0000_0400, rdata);         // D -> victim slot 3.
        check(cache0.victim.debug_fifo_pointer == 2'd0,
              "FIFO pointer wraps after four victim insertions");
        cpu0_read (32'h0000_0440, rdata);         // E replaces slot 0.
        check(memory.mem[48][31:0] == 32'hcafe_babe,
              "replacing an M victim entry writes it back before reuse");
        check(cache0.victim.block_addr[0] == (32'h0000_0400 >> 4),
              "FIFO replacement installs the displaced 0x400 L1 block");
        check(cache0.victim.mesi_state[0] == MESI_E,
              "clean replacement preserves the displaced block state");

        if (errors == 0) begin
            $display("\nCACHE/MESI TESTS PASS");
        end else begin
            $display("\nCACHE/MESI TESTS FAIL: %0d error(s)", errors);
            $finish;
        end
        $finish;
    end
endmodule

`default_nettype wire
