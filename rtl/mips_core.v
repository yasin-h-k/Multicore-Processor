`timescale 1ns/1ps
`default_nettype none

module mips_core #(
    parameter integer CORE_ID = 0,
    parameter IMEM_FILE = ""
) (
    input  wire        clk,
    input  wire        reset,

    output wire dcache_req,
    output wire dcache_we,
    output wire [31:0] dcache_addr,
    output wire [31:0] dcache_wdata,
    input  wire [31:0] dcache_rdata,
    input  wire        dcache_ready,

    output wire [31:0] debug_pc,
    output wire debug_mem_stall,
    output wire debug_load_use_stall,
    output wire debug_control_flush
);
    // Program counter and instruction fetch.
    reg [31:0] pc;
    wire [31:0] fetched_instr;

    instruction_memory #(
        .MEM_FILE(IMEM_FILE),
        .WORDS(256)
    ) imem (
        .addr(pc),
        .instr(fetched_instr)
    );

    // IF/ID pipeline register.
    reg        ifid_valid;
    reg [31:0] ifid_pc4;
    reg [31:0] ifid_instr;

    // Decode fields and control.
    wire [5:0] id_opcode;
    wire [5:0] id_funct;
    wire [4:0] id_rs;
    wire [4:0] id_rt;
    wire [4:0] id_rd;
    wire [15:0] id_imm16;
    wire [25:0] id_jump_index;

    wire id_reg_dst;
    wire id_alu_src;
    wire id_mem_to_reg;
    wire id_reg_write;
    wire id_mem_read;
    wire id_mem_write;
    wire id_branch_eq;
    wire id_branch_ne;
    wire id_jump;
    wire id_imm_zero_extend;
    wire [2:0] id_alu_op;
    reg [31:0] id_imm_ext;

    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;
    wire       rf_write_enable;
    wire [4:0] rf_write_addr;
    wire [31:0] rf_write_data;

    assign id_opcode     = ifid_instr[31:26];
    assign id_rs         = ifid_instr[25:21];
    assign id_rt         = ifid_instr[20:16];
    assign id_rd         = ifid_instr[15:11];
    assign id_imm16      = ifid_instr[15:0];
    assign id_funct      = ifid_instr[5:0];
    assign id_jump_index = ifid_instr[25:0];

    control_unit control (
        .opcode(id_opcode),
        .funct(id_funct),
        .reg_dst(id_reg_dst),
        .alu_src(id_alu_src),
        .mem_to_reg(id_mem_to_reg),
        .reg_write(id_reg_write),
        .mem_read(id_mem_read),
        .mem_write(id_mem_write),
        .branch_eq(id_branch_eq),
        .branch_ne(id_branch_ne),
        .jump(id_jump),
        .imm_zero_extend(id_imm_zero_extend),
        .alu_op(id_alu_op)
    );

    always @* begin
        if (id_imm_zero_extend) begin
            id_imm_ext = {16'd0, id_imm16};
        end else begin
            id_imm_ext = {{16{id_imm16[15]}}, id_imm16};
        end
    end

    // ID/EX pipeline register.
    reg        idex_valid;
    reg [31:0] idex_pc4;
    reg [31:0] idex_rdata1;
    reg [31:0] idex_rdata2;
    reg [31:0] idex_imm;
    reg [25:0] idex_jump_index;
    reg [5:0]  idex_funct;
    reg [4:0]  idex_rs;
    reg [4:0]  idex_rt;
    reg [4:0]  idex_rd;
    reg        idex_reg_dst;
    reg        idex_alu_src;
    reg        idex_mem_to_reg;
    reg        idex_reg_write;
    reg        idex_mem_read;
    reg        idex_mem_write;
    reg        idex_branch_eq;
    reg        idex_branch_ne;
    reg        idex_jump;
    reg [2:0]  idex_alu_op;

    // EX/MEM pipeline register.
    reg        exmem_valid;
    reg [31:0] exmem_alu_result;
    reg [31:0] exmem_store_data;
    reg [4:0]  exmem_dest;
    reg        exmem_mem_to_reg;
    reg        exmem_reg_write;
    reg        exmem_mem_read;
    reg        exmem_mem_write;

    // MEM/WB pipeline register.
    reg        memwb_valid;
    reg [31:0] memwb_alu_result;
    reg [31:0] memwb_mem_data;
    reg [4:0]  memwb_dest;
    reg        memwb_mem_to_reg;
    reg        memwb_reg_write;

    assign rf_write_addr = memwb_dest;
    assign rf_write_data = memwb_mem_to_reg ? memwb_mem_data : memwb_alu_result;

    wire mem_stall;
    assign mem_stall = exmem_valid && (exmem_mem_read || exmem_mem_write) &&
                       !dcache_ready;
    assign rf_write_enable = memwb_valid && memwb_reg_write && !mem_stall;

    register_file rf (
        .clk(clk),
        .reset(reset),
        .we(rf_write_enable),
        .waddr(rf_write_addr),
        .wdata(rf_write_data),
        .raddr1(id_rs),
        .raddr2(id_rt),
        .rdata1(rf_rdata1),
        .rdata2(rf_rdata2)
    );

    wire load_use_stall;
    hazard_unit hazard (
        .idex_mem_read(idex_valid && idex_mem_read),
        .idex_rt(idex_rt),
        .ifid_instr(ifid_instr),
        .load_use_stall(load_use_stall)
    );

    // EX-stage forwarding and ALU.
    wire [1:0] forward_a;
    wire [1:0] forward_b;
    reg [31:0] forwarded_a;
    reg [31:0] forwarded_b;
    wire [31:0] alu_operand_b;
    wire [3:0] ex_alu_ctrl;
    wire [31:0] ex_alu_result;
    wire       ex_alu_zero;
    wire [4:0] ex_dest;

    forwarding_unit forwarding (
        .exmem_reg_write(exmem_valid && exmem_reg_write),
        .exmem_mem_read(exmem_mem_read),
        .exmem_rd(exmem_dest),
        .memwb_reg_write(memwb_valid && memwb_reg_write),
        .memwb_rd(memwb_dest),
        .idex_rs(idex_rs),
        .idex_rt(idex_rt),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    always @* begin
        case (forward_a)
            2'b10: forwarded_a = exmem_alu_result;
            2'b01: forwarded_a = rf_write_data;
            default: forwarded_a = idex_rdata1;
        endcase

        case (forward_b)
            2'b10: forwarded_b = exmem_alu_result;
            2'b01: forwarded_b = rf_write_data;
            default: forwarded_b = idex_rdata2;
        endcase
    end

    assign alu_operand_b = idex_alu_src ? idex_imm : forwarded_b;

    alu_control alu_decode (
        .alu_op(idex_alu_op),
        .funct(idex_funct),
        .alu_ctrl(ex_alu_ctrl)
    );

    alu execute_alu (
        .a(forwarded_a),
        .b(alu_operand_b),
        .control(ex_alu_ctrl),
        .result(ex_alu_result),
        .zero(ex_alu_zero)
    );

    assign ex_dest = idex_reg_dst ? idex_rd : idex_rt;

    wire [31:0] branch_target;
    wire [31:0] jump_target;
    wire       branch_equal;
    wire       branch_taken;
    wire       jump_taken;
    wire       control_flush;
    wire [31:0] control_target;

    assign branch_target = idex_pc4 + (idex_imm << 2);
    assign jump_target   = {idex_pc4[31:28], idex_jump_index, 2'b00};
    assign branch_equal  = ex_alu_zero;
    assign branch_taken  = idex_valid &&
                           ((idex_branch_eq && branch_equal) ||
                            (idex_branch_ne && !branch_equal));
    assign jump_taken    = idex_valid && idex_jump;
    assign control_flush = branch_taken || jump_taken;
    assign control_target = jump_taken ? jump_target : branch_target;

    // Cache interface. Address and store data remain stable while EX/MEM is held.
    assign dcache_req   = exmem_valid && (exmem_mem_read || exmem_mem_write);
    assign dcache_we    = exmem_mem_write;
    assign dcache_addr  = exmem_alu_result;
    assign dcache_wdata = exmem_store_data;

    assign debug_pc                 = pc;
    assign debug_mem_stall          = mem_stall;
    assign debug_load_use_stall     = load_use_stall;
    assign debug_control_flush      = control_flush;

    always @(posedge clk) begin
        if (reset) begin
            pc                  <= 32'd0;
            ifid_valid          <= 1'b0;
            ifid_pc4            <= 32'd0;
            ifid_instr          <= 32'd0;

            idex_valid          <= 1'b0;
            idex_pc4            <= 32'd0;
            idex_rdata1         <= 32'd0;
            idex_rdata2         <= 32'd0;
            idex_imm            <= 32'd0;
            idex_jump_index     <= 26'd0;
            idex_funct          <= 6'd0;
            idex_rs             <= 5'd0;
            idex_rt             <= 5'd0;
            idex_rd             <= 5'd0;
            idex_reg_dst        <= 1'b0;
            idex_alu_src        <= 1'b0;
            idex_mem_to_reg     <= 1'b0;
            idex_reg_write      <= 1'b0;
            idex_mem_read       <= 1'b0;
            idex_mem_write      <= 1'b0;
            idex_branch_eq      <= 1'b0;
            idex_branch_ne      <= 1'b0;
            idex_jump           <= 1'b0;
            idex_alu_op         <= 3'd0;

            exmem_valid         <= 1'b0;
            exmem_alu_result    <= 32'd0;
            exmem_store_data    <= 32'd0;
            exmem_dest          <= 5'd0;
            exmem_mem_to_reg    <= 1'b0;
            exmem_reg_write     <= 1'b0;
            exmem_mem_read      <= 1'b0;
            exmem_mem_write     <= 1'b0;

            memwb_valid         <= 1'b0;
            memwb_alu_result    <= 32'd0;
            memwb_mem_data      <= 32'd0;
            memwb_dest          <= 5'd0;
            memwb_mem_to_reg    <= 1'b0;
            memwb_reg_write     <= 1'b0;
        end else if (mem_stall) begin
            // Freeze PC and every pipeline register. WB is also gated so an
            // older instruction cannot commit repeatedly during a long miss.
        end else begin
            // MEM/WB always receives the current EX/MEM instruction when the
            // memory stage is not stalled.
            memwb_valid      <= exmem_valid;
            memwb_alu_result <= exmem_alu_result;
            memwb_mem_data   <= dcache_rdata;
            memwb_dest       <= exmem_dest;
            memwb_mem_to_reg <= exmem_mem_to_reg;
            memwb_reg_write  <= exmem_reg_write;

            // EX/MEM receives the current ID/EX instruction.
            exmem_valid      <= idex_valid;
            exmem_alu_result <= ex_alu_result;
            exmem_store_data <= forwarded_b;
            exmem_dest       <= ex_dest;
            exmem_mem_to_reg <= idex_mem_to_reg;
            exmem_reg_write  <= idex_reg_write;
            exmem_mem_read   <= idex_mem_read;
            exmem_mem_write  <= idex_mem_write;

            if (control_flush) begin
                pc         <= control_target;
                ifid_valid <= 1'b0;
                ifid_pc4   <= 32'd0;
                ifid_instr <= 32'd0;
                idex_valid <= 1'b0;
                idex_reg_write <= 1'b0;
                idex_mem_read  <= 1'b0;
                idex_mem_write <= 1'b0;
                idex_branch_eq <= 1'b0;
                idex_branch_ne <= 1'b0;
                idex_jump      <= 1'b0;
            end else if (load_use_stall) begin
                // Hold PC and IF/ID, and insert one bubble into ID/EX.
                idex_valid     <= 1'b0;
                idex_reg_write <= 1'b0;
                idex_mem_read  <= 1'b0;
                idex_mem_write <= 1'b0;
                idex_branch_eq <= 1'b0;
                idex_branch_ne <= 1'b0;
                idex_jump      <= 1'b0;
            end else begin
                pc         <= pc + 32'd4;
                ifid_valid <= 1'b1;
                ifid_pc4   <= pc + 32'd4;
                ifid_instr <= fetched_instr;

                idex_valid      <= ifid_valid;
                idex_pc4        <= ifid_pc4;
                idex_rdata1     <= rf_rdata1;
                idex_rdata2     <= rf_rdata2;
                idex_imm        <= id_imm_ext;
                idex_jump_index <= id_jump_index;
                idex_funct      <= id_funct;
                idex_rs         <= id_rs;
                idex_rt         <= id_rt;
                idex_rd         <= id_rd;
                idex_reg_dst    <= id_reg_dst;
                idex_alu_src    <= id_alu_src;
                idex_mem_to_reg <= id_mem_to_reg;
                idex_reg_write  <= id_reg_write;
                idex_mem_read   <= id_mem_read;
                idex_mem_write  <= id_mem_write;
                idex_branch_eq  <= id_branch_eq;
                idex_branch_ne  <= id_branch_ne;
                idex_jump       <= id_jump;
                idex_alu_op     <= id_alu_op;
            end
        end
    end
endmodule

`default_nettype wire
