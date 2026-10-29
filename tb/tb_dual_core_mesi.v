`timescale 1ns/1ps
`default_nettype none

module tb_dual_core_mesi;
    reg clk;
    reg reset;
    integer errors;
    integer cycles;
    integer t3_load_commit_count;

    wire [31:0] pc0, pc1;
    wire stall0, stall1;
    wire load_use0, load_use1;
    wire flush0, flush1;
    wire grant0, grant1;
    wire [2:0] bus_state;
    wire bus_owner;
    wire [1:0] bus_cmd;

    reg saw_stall0;
    reg saw_stall1;
    reg saw_load_use0;
    reg saw_flush0;
    reg saw_flush1;
    reg previous_stall0;
    reg previous_stall1;
    reg [31:0] previous_pc0;
    reg [31:0] previous_pc1;

    dual_core_mips_top dut (
        .clk(clk),
        .reset(reset),
        .debug_pc0(pc0),
        .debug_pc1(pc1),
        .debug_stall0(stall0),
        .debug_stall1(stall1),
        .debug_load_use0(load_use0),
        .debug_load_use1(load_use1),
        .debug_flush0(flush0),
        .debug_flush1(flush1),
        .debug_grant0(grant0),
        .debug_grant1(grant1),
        .debug_bus_state(bus_state),
        .debug_bus_owner(bus_owner),
        .debug_bus_cmd(bus_cmd)
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

    always @(posedge clk) begin
        if (reset) begin
            saw_stall0          <= 1'b0;
            saw_stall1          <= 1'b0;
            saw_load_use0       <= 1'b0;
            saw_flush0          <= 1'b0;
            saw_flush1          <= 1'b0;
            previous_stall0     <= 1'b0;
            previous_stall1     <= 1'b0;
            previous_pc0        <= 32'd0;
            previous_pc1        <= 32'd0;
            t3_load_commit_count <= 0;
        end else begin
            if (stall0) saw_stall0 <= 1'b1;
            if (stall1) saw_stall1 <= 1'b1;
            if (load_use0) saw_load_use0 <= 1'b1;
            if (flush0) saw_flush0 <= 1'b1;
            if (flush1) saw_flush1 <= 1'b1;

            // If a cache stall persists across complete cycles, PC must not move.
            if (previous_stall0 && stall0 && (pc0 !== previous_pc0)) begin
                errors = errors + 1;
                $display("[FAIL] core 0 PC moved during persistent cache stall");
            end
            if (previous_stall1 && stall1 && (pc1 !== previous_pc1)) begin
                errors = errors + 1;
                $display("[FAIL] core 1 PC moved during persistent cache stall");
            end

            previous_stall0 <= stall0;
            previous_stall1 <= stall1;
            previous_pc0    <= pc0;
            previous_pc1    <= pc1;

            // The load into $t3 in core 0 must commit exactly once.
            if (dut.core0.rf_write_enable && (dut.core0.rf_write_addr == 5'd11)) begin
                t3_load_commit_count <= t3_load_commit_count + 1;
            end
        end
    end

    initial begin
        $dumpfile("build/dual_core_mesi.vcd");
        $dumpvars(0, tb_dual_core_mesi);

        clk = 1'b0;
        reset = 1'b1;
        errors = 0;
        cycles = 0;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        while (((dut.core0.rf.regs[18] !== 32'd1) ||
                (dut.core1.rf.regs[18] !== 32'd1)) && (cycles < 2000)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        check(cycles < 2000, "both programs reached their completion flags");

        // Allow the final writes and debug monitors to settle.
        repeat (6) @(posedge clk);

        $display("\n--- Core 0 architectural checks ---");
        check(dut.core0.rf.regs[8]  == 32'd5,  "$t0 = 5");
        check(dut.core0.rf.regs[9]  == 32'd8,  "ALU forwarding produced $t1 = 8");
        check(dut.core0.rf.regs[10] == 32'd13, "dual-source forwarding produced $t2 = 13");
        check(dut.core0.rf.regs[11] == 32'd13, "load returned stored value");
        check(dut.core0.rf.regs[12] == 32'd18, "load-use result $t4 = 18");
        check(dut.core0.rf.regs[13] == 32'd7,  "taken branch flushed wrong-path writes");
        check(dut.core0.rf.regs[14] == 32'd9,  "jump flushed wrong-path write");
        check(dut.core0.rf.regs[15] == 32'd18, "post-eviction load returned 18");
        check(dut.core0.rf.regs[0]  == 32'd0,  "$zero remains zero");

        $display("\n--- Core 1 architectural checks ---");
        check(dut.core1.rf.regs[8]  == 32'h0000_00f0, "ori zero extension is correct");
        check(dut.core1.rf.regs[9]  == 32'h0000_00f0, "core 1 load value is correct");
        check(dut.core1.rf.regs[10] == 32'd0, "sub result is zero");
        check(dut.core1.rf.regs[11] == 32'd11, "bne not-taken and jump behavior are correct");

        $display("\n--- Pipeline/cache behavioral checks ---");
        check(saw_stall0, "core 0 experienced a cache/coherence stall");
        check(saw_stall1, "core 1 experienced a cache/coherence stall");
        check(saw_load_use0, "load-use hazard detector inserted a bubble");
        check(saw_flush0, "core 0 generated branch/jump flushes");
        check(saw_flush1, "core 1 generated a jump flush");
        check(t3_load_commit_count == 1, "stalled load committed exactly once");

        // 0x300 and 0x340 map to the same direct-mapped L1 index. With the
        // bonus victim cache enabled, the dirty 0x300 block moves to victim
        // slot 0 instead of being written back immediately.
        check(dut.cache0.victim.block_addr[0] == (32'h0000_0300 >> 4),
              "core 0 victim cache stores the displaced 0x300 block");
        check(dut.cache0.victim.mesi_state[0] == 2'b11,
              "displaced 0x300 block preserves Modified state");
        check(dut.cache0.victim.data_block[0][31:0] == 32'd13,
              "victim cache preserves dirty 0x300 data");
        check(dut.memory.mem[48][31:0] == 32'd0,
              "main memory stays stale until an M victim entry is replaced or snooped");
        check(dut.cache0.tags[0] == (32'h0000_0340 >> 6),
              "core 0 installed the 0x340 tag at index 0");
        check(dut.cache0.data_lines[0][31:0] == 32'd18,
              "core 0 L1 contains the final 0x340 word");

        if (errors == 0) begin
            $display("\nDUAL-CORE PIPELINE TESTS PASS");
        end else begin
            $display("\nDUAL-CORE PIPELINE TESTS FAIL: %0d error(s)", errors);
            $finish;
        end
        $finish;
    end
endmodule

`default_nettype wire
