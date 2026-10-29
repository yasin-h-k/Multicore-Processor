`timescale 1ns/1ps
`default_nettype none

module dual_core_mips_top #(
    parameter CORE0_IMEM_FILE = "mem/core0_program.mem",
    parameter CORE1_IMEM_FILE = "mem/core1_program.mem",
    parameter DATA_MEM_FILE   = "mem/data_memory.mem",
    parameter integer MEMORY_LATENCY = 3,
    parameter integer ENABLE_VICTIM_CACHE = 1
) (
    input  wire        clk,
    input  wire        reset,
    output wire [31:0] debug_pc0,
    output wire [31:0] debug_pc1,
    output wire debug_stall0,
    output wire debug_stall1,
    output wire debug_load_use0,
    output wire debug_load_use1,
    output wire debug_flush0,
    output wire debug_flush1,
    output wire debug_grant0,
    output wire debug_grant1,
    output wire [2:0] debug_bus_state,
    output wire debug_bus_owner,
    output wire [1:0] debug_bus_cmd
);
    // Core-to-cache interfaces.
    wire c0_cpu_req, c0_cpu_we, c0_cpu_ready, c0_cpu_stall;
    wire [31:0] c0_cpu_addr, c0_cpu_wdata, c0_cpu_rdata;
    wire c1_cpu_req, c1_cpu_we, c1_cpu_ready, c1_cpu_stall;
    wire [31:0] c1_cpu_addr, c1_cpu_wdata, c1_cpu_rdata;

    // Cache-to-bus interfaces.
    wire c0_bus_req, c0_bus_done, c0_bus_shared;
    wire [1:0] c0_bus_cmd;
    wire [31:0] c0_bus_addr;
    wire [127:0] c0_bus_wdata, c0_bus_rdata;
    wire c1_bus_req, c1_bus_done, c1_bus_shared;
    wire [1:0] c1_bus_cmd;
    wire [31:0] c1_bus_addr;
    wire [127:0] c1_bus_wdata, c1_bus_rdata;

    // Snoop interfaces.
    wire snoop0_valid, snoop0_hit, snoop0_modified;
    wire [1:0] snoop0_cmd;
    wire [31:0] snoop0_addr;
    wire [127:0] snoop0_data;
    wire snoop1_valid, snoop1_hit, snoop1_modified;
    wire [1:0] snoop1_cmd;
    wire [31:0] snoop1_addr;
    wire [127:0] snoop1_data;

    // Main-memory interface.
    wire mem_req, mem_we, mem_ready;
    wire [31:0] mem_addr;
    wire [127:0] mem_wdata, mem_rdata;
    wire mem_debug_write, mem_debug_read;

    wire cache0_hit_pulse, cache0_miss_pulse;
    wire [1:0] cache0_debug_index;
    wire [25:0] cache0_debug_tag;
    wire [3:0] cache0_debug_state;
    wire cache0_victim_hit;
    wire [1:0] cache0_victim_fifo;
    wire cache1_hit_pulse, cache1_miss_pulse;
    wire [1:0] cache1_debug_index;
    wire [25:0] cache1_debug_tag;
    wire [3:0] cache1_debug_state;
    wire cache1_victim_hit;
    wire [1:0] cache1_victim_fifo;

    mips_core #(
        .CORE_ID(0),
        .IMEM_FILE(CORE0_IMEM_FILE)
    ) core0 (
        .clk(clk),
        .reset(reset),
        .dcache_req(c0_cpu_req),
        .dcache_we(c0_cpu_we),
        .dcache_addr(c0_cpu_addr),
        .dcache_wdata(c0_cpu_wdata),
        .dcache_rdata(c0_cpu_rdata),
        .dcache_ready(c0_cpu_ready),
        .debug_pc(debug_pc0),
        .debug_mem_stall(debug_stall0),
        .debug_load_use_stall(debug_load_use0),
        .debug_control_flush(debug_flush0)
    );

    mips_core #(
        .CORE_ID(1),
        .IMEM_FILE(CORE1_IMEM_FILE)
    ) core1 (
        .clk(clk),
        .reset(reset),
        .dcache_req(c1_cpu_req),
        .dcache_we(c1_cpu_we),
        .dcache_addr(c1_cpu_addr),
        .dcache_wdata(c1_cpu_wdata),
        .dcache_rdata(c1_cpu_rdata),
        .dcache_ready(c1_cpu_ready),
        .debug_pc(debug_pc1),
        .debug_mem_stall(debug_stall1),
        .debug_load_use_stall(debug_load_use1),
        .debug_control_flush(debug_flush1)
    );

    l1_data_cache #(
        .CACHE_ID(0),
        .ENABLE_VICTIM_CACHE(ENABLE_VICTIM_CACHE)
    ) cache0 (
        .clk(clk),
        .reset(reset),
        .cpu_req(c0_cpu_req),
        .cpu_we(c0_cpu_we),
        .cpu_addr(c0_cpu_addr),
        .cpu_wdata(c0_cpu_wdata),
        .cpu_rdata(c0_cpu_rdata),
        .cpu_ready(c0_cpu_ready),
        .cpu_stall(c0_cpu_stall),
        .bus_req(c0_bus_req),
        .bus_cmd(c0_bus_cmd),
        .bus_addr(c0_bus_addr),
        .bus_wdata(c0_bus_wdata),
        .bus_done(c0_bus_done),
        .bus_rdata(c0_bus_rdata),
        .bus_shared(c0_bus_shared),
        .snoop_valid(snoop0_valid),
        .snoop_cmd(snoop0_cmd),
        .snoop_addr(snoop0_addr),
        .snoop_hit(snoop0_hit),
        .snoop_modified(snoop0_modified),
        .snoop_data(snoop0_data),
        .debug_hit_pulse(cache0_hit_pulse),
        .debug_miss_pulse(cache0_miss_pulse),
        .debug_victim_hit_pulse(cache0_victim_hit),
        .debug_cpu_index(cache0_debug_index),
        .debug_cpu_tag(cache0_debug_tag),
        .debug_fsm_state(cache0_debug_state),
        .debug_victim_fifo(cache0_victim_fifo)
    );

    l1_data_cache #(
        .CACHE_ID(1),
        .ENABLE_VICTIM_CACHE(ENABLE_VICTIM_CACHE)
    ) cache1 (
        .clk(clk),
        .reset(reset),
        .cpu_req(c1_cpu_req),
        .cpu_we(c1_cpu_we),
        .cpu_addr(c1_cpu_addr),
        .cpu_wdata(c1_cpu_wdata),
        .cpu_rdata(c1_cpu_rdata),
        .cpu_ready(c1_cpu_ready),
        .cpu_stall(c1_cpu_stall),
        .bus_req(c1_bus_req),
        .bus_cmd(c1_bus_cmd),
        .bus_addr(c1_bus_addr),
        .bus_wdata(c1_bus_wdata),
        .bus_done(c1_bus_done),
        .bus_rdata(c1_bus_rdata),
        .bus_shared(c1_bus_shared),
        .snoop_valid(snoop1_valid),
        .snoop_cmd(snoop1_cmd),
        .snoop_addr(snoop1_addr),
        .snoop_hit(snoop1_hit),
        .snoop_modified(snoop1_modified),
        .snoop_data(snoop1_data),
        .debug_hit_pulse(cache1_hit_pulse),
        .debug_miss_pulse(cache1_miss_pulse),
        .debug_victim_hit_pulse(cache1_victim_hit),
        .debug_cpu_index(cache1_debug_index),
        .debug_cpu_tag(cache1_debug_tag),
        .debug_fsm_state(cache1_debug_state),
        .debug_victim_fifo(cache1_victim_fifo)
    );

    bus_arbiter arbiter (
        .clk(clk),
        .reset(reset),
        .c0_req(c0_bus_req),
        .c0_cmd(c0_bus_cmd),
        .c0_addr(c0_bus_addr),
        .c0_wdata(c0_bus_wdata),
        .c0_done(c0_bus_done),
        .c0_rdata(c0_bus_rdata),
        .c0_shared(c0_bus_shared),
        .c0_grant_pulse(debug_grant0),
        .c1_req(c1_bus_req),
        .c1_cmd(c1_bus_cmd),
        .c1_addr(c1_bus_addr),
        .c1_wdata(c1_bus_wdata),
        .c1_done(c1_bus_done),
        .c1_rdata(c1_bus_rdata),
        .c1_shared(c1_bus_shared),
        .c1_grant_pulse(debug_grant1),
        .snoop0_valid(snoop0_valid),
        .snoop0_cmd(snoop0_cmd),
        .snoop0_addr(snoop0_addr),
        .snoop0_hit(snoop0_hit),
        .snoop0_modified(snoop0_modified),
        .snoop0_data(snoop0_data),
        .snoop1_valid(snoop1_valid),
        .snoop1_cmd(snoop1_cmd),
        .snoop1_addr(snoop1_addr),
        .snoop1_hit(snoop1_hit),
        .snoop1_modified(snoop1_modified),
        .snoop1_data(snoop1_data),
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),
        .debug_state(debug_bus_state),
        .debug_owner(debug_bus_owner),
        .debug_cmd(debug_bus_cmd)
    );

    shared_main_memory #(
        .BLOCKS(256),
        .LATENCY(MEMORY_LATENCY),
        .INIT_FILE(DATA_MEM_FILE)
    ) memory (
        .clk(clk),
        .reset(reset),
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),
        .debug_write_pulse(mem_debug_write),
        .debug_read_pulse(mem_debug_read)
    );
endmodule

`default_nettype wire
