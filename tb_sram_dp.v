// =============================================================================
// tb_sram_dp.v  --  self-contained testbench for sram_dp.v
// -----------------------------------------------------------------------------
// 独立运行：只依赖 sram_dp.v，不 include / 不例化任何其他模块。
//   iverilog -o sim.out sram_dp.v tb_sram_dp.v && vvp sim.out
//
// cyc 参数顺序：we_a, addr_a, wdata_a, we_b, addr_b, wdata_b
// 激励在 negedge 驱动，返回时两端口的 rdata 均已有效。
//
// 覆盖：写后读回 / 连续写不同地址再连续读 / we=0 保持 / 边界地址 / 两端口
//       同时读不同地址 / 一端口写另一端口读 / 写冲突 A 优先 / 不同地址同时写。
// =============================================================================
`timescale 1ns/1ps

module tb_sram_dp;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 10;
    localparam DEPTH      = 1 << ADDR_WIDTH;
    localparam ADDR_MAX   = DEPTH - 1;

    reg                      clk = 1'b0;
    reg                      rst;
    reg                      we_a, we_b;
    reg  [ADDR_WIDTH-1:0]    addr_a, addr_b;
    reg  [DATA_WIDTH-1:0]    wdata_a, wdata_b;
    wire [DATA_WIDTH-1:0]    rdata_a, rdata_b;

    integer tests;
    integer errors;

    sram_dp #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .we_a    (we_a),
        .we_b    (we_b),
        .addr_a  (addr_a),
        .addr_b  (addr_b),
        .wdata_a (wdata_a),
        .wdata_b (wdata_b),
        .rdata_a (rdata_a),
        .rdata_b (rdata_b)
    );

    always #5 clk = ~clk;

    task check;
        input [8*64:1]          tname;
        input [DATA_WIDTH-1:0]  got;
        input [DATA_WIDTH-1:0]  exp;
        begin
            tests = tests + 1;
            if (got !== exp) begin
                $display("[FAIL] %0s got=0x%08h exp=0x%08h", tname, got, exp);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s data=0x%08h", tname, got);
            end
        end
    endtask

    // 一个完整时钟周期，两端口激励同时给出（这是并发测试的关键）
    task cyc;
        input                   i_we_a;
        input [ADDR_WIDTH-1:0]  i_addr_a;
        input [DATA_WIDTH-1:0]  i_wdata_a;
        input                   i_we_b;
        input [ADDR_WIDTH-1:0]  i_addr_b;
        input [DATA_WIDTH-1:0]  i_wdata_b;
        begin
            @(negedge clk);
            we_a    = i_we_a;
            addr_a  = i_addr_a;
            wdata_a = i_wdata_a;
            we_b    = i_we_b;
            addr_b  = i_addr_b;
            wdata_b = i_wdata_b;
            @(negedge clk);
        end
    endtask

    initial begin
        tests   = 0;
        errors  = 0;
        rst     = 1'b1;
        we_a    = 1'b0;
        we_b    = 1'b0;
        addr_a  = {ADDR_WIDTH{1'b0}};
        addr_b  = {ADDR_WIDTH{1'b0}};
        wdata_a = {DATA_WIDTH{1'b0}};
        wdata_b = {DATA_WIDTH{1'b0}};

        repeat (2) @(negedge clk);
        rst = 1'b0;
        check("TC01 sync reset clears rdata_a", rdata_a, 32'h0000_0000);
        check("TC02 sync reset clears rdata_b", rdata_b, 32'h0000_0000);

        // ---- A 端口写后读回 ----
        cyc(1'b1, 10'h040, 32'hAAAA_0000, 1'b0, 10'h000, 32'h0);
        cyc(1'b0, 10'h040, 32'h0,        1'b0, 10'h000, 32'h0);
        check("TC03 port A write then read back", rdata_a, 32'hAAAA_0000);

        // ---- A 写、B 读：两端口共享同一物理阵列 ----
        cyc(1'b1, 10'h041, 32'hBBBB_0000, 1'b0, 10'h000, 32'h0);
        cyc(1'b0, 10'h000, 32'h0,        1'b0, 10'h041, 32'h0);
        check("TC04 port B reads what port A wrote", rdata_b, 32'hBBBB_0000);

        // ---- B 写、A 读 ----
        cyc(1'b0, 10'h000, 32'h0,        1'b1, 10'h042, 32'hCCCC_0000);
        cyc(1'b0, 10'h042, 32'h0,        1'b0, 10'h000, 32'h0);
        check("TC05 port A reads what port B wrote", rdata_a, 32'hCCCC_0000);

        // ---- 连续写 4 个不同地址，再连续读：地址译码 ----
        cyc(1'b1, 10'h010, 32'h1111_1111, 1'b0, 10'h000, 32'h0);
        cyc(1'b1, 10'h011, 32'h2222_2222, 1'b0, 10'h000, 32'h0);
        cyc(1'b1, 10'h012, 32'h3333_3333, 1'b0, 10'h000, 32'h0);
        cyc(1'b1, 10'h013, 32'h4444_4444, 1'b0, 10'h000, 32'h0);
        cyc(1'b0, 10'h000, 32'h0, 1'b0, 10'h010, 32'h0);
        check("TC06 addr decode 0x010", rdata_b, 32'h1111_1111);
        cyc(1'b0, 10'h000, 32'h0, 1'b0, 10'h011, 32'h0);
        check("TC07 addr decode 0x011", rdata_b, 32'h2222_2222);
        cyc(1'b0, 10'h000, 32'h0, 1'b0, 10'h012, 32'h0);
        check("TC08 addr decode 0x012", rdata_b, 32'h3333_3333);
        cyc(1'b0, 10'h000, 32'h0, 1'b0, 10'h013, 32'h0);
        check("TC09 addr decode 0x013", rdata_b, 32'h4444_4444);

        // ---- 边界地址 0 与最大值 ----
        cyc(1'b1, 10'h000, 32'hFFFF_FFFF, 1'b0, 10'h000, 32'h0);
        cyc(1'b0, 10'h000, 32'h0,        1'b0, 10'h000, 32'h0);
        check("TC10 boundary addr 0", rdata_b, 32'hFFFF_FFFF);
        cyc(1'b1, ADDR_MAX, 32'h0000_0001, 1'b0, 10'h000, 32'h0);
        cyc(1'b0, 10'h000, 32'h0,        1'b0, ADDR_MAX, 32'h0);
        check("TC11 boundary addr MAX", rdata_b, 32'h0000_0001);

        // ---- we_a = we_b = 0：两端口读数据保持不变，wdata 不改写阵列 ----
        cyc(1'b1, 10'h020, 32'hCAFE_BABE, 1'b0, 10'h000, 32'h0);
        cyc(1'b0, 10'h020, 32'hDEAD_DEAD, 1'b0, 10'h020, 32'hDEAD_DEAD);
        check("TC12 we=0 hold on port A", rdata_a, 32'hCAFE_BABE);
        check("TC13 we=0 hold on port B", rdata_b, 32'hCAFE_BABE);
        cyc(1'b0, 10'h020, 32'hDEAD_DEAD, 1'b0, 10'h020, 32'hDEAD_DEAD);
        check("TC14 we=0 hold, second cycle", rdata_a, 32'hCAFE_BABE);

        // ---- 两端口同时读不同地址 ----
        cyc(1'b0, 10'h010, 32'h0, 1'b0, 10'h011, 32'h0);
        check("TC15 simultaneous read A at 0x010", rdata_a, 32'h1111_1111);
        check("TC16 simultaneous read B at 0x011", rdata_b, 32'h2222_2222);

        // ---- 同拍一端口写、另一端口读不同地址 ----
        cyc(1'b1, 10'h050, 32'h0DAD_0000, 1'b0, 10'h012, 32'h0);
        check("TC17 B reads while A writes elsewhere", rdata_b, 32'h3333_3333);
        cyc(1'b0, 10'h050, 32'h0, 1'b0, 10'h000, 32'h0);
        check("TC18 A write visible at next read", rdata_a, 32'h0DAD_0000);

        // ---- 同拍 A 写、B 读同一地址：read-first ----
        cyc(1'b1, 10'h051, 32'h0BAD_F00D, 1'b0, 10'h000, 32'h0);
        cyc(1'b1, 10'h051, 32'h1234_5678, 1'b0, 10'h051, 32'h0);
        check("TC19 same addr write/read is read-first", rdata_b, 32'h0BAD_F00D);
        cyc(1'b0, 10'h000, 32'h0, 1'b0, 10'h051, 32'h0);
        check("TC20 new value visible at next read", rdata_b, 32'h1234_5678);

        // ---- 写冲突：同拍 A、B 写同一地址，A 优先，B 的写被丢弃 ----
        cyc(1'b1, 10'h060, 32'h0ABC_DEF0, 1'b0, 10'h000, 32'h0);
        cyc(1'b1, 10'h060, 32'hAAAA_5555, 1'b1, 10'h060, 32'h5555_AAAA);
        check("TC21 conflict cycle is read-first", rdata_a, 32'h0ABC_DEF0);
        cyc(1'b0, 10'h060, 32'h0, 1'b0, 10'h000, 32'h0);
        check("TC22 conflict result, port A wins", rdata_a, 32'hAAAA_5555);
        cyc(1'b0, 10'h000, 32'h0, 1'b0, 10'h060, 32'h0);
        check("TC23 conflict result, port B write dropped", rdata_b, 32'hAAAA_5555);

        // ---- 两端口同拍写不同地址：两个写都生效（无冲突）----
        cyc(1'b1, 10'h070, 32'h7777_0000, 1'b1, 10'h071, 32'h8888_0000);
        cyc(1'b0, 10'h070, 32'h0,        1'b0, 10'h071, 32'h0);
        check("TC24 distinct addr write, A effective", rdata_a, 32'h7777_0000);
        check("TC25 distinct addr write, B effective", rdata_b, 32'h8888_0000);

        #20;
        $display("------------------------------------------------------------");
        if (errors == 0)
            $display("[SUMMARY] tb_sram_dp : %0d PASS, 0 FAIL  => ALL PASS", tests);
        else
            $display("[SUMMARY] tb_sram_dp : %0d checks, %0d FAIL  => TEST FAIL",
                     tests, errors);
        $finish;
    end

    initial begin
        #20000;
        $display("[TIMEOUT] tb_sram_dp did not finish");
        $finish;
    end

endmodule
