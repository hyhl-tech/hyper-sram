// =============================================================================
// tb_sram_sync.v  --  self-contained testbench for sram_sync.v
// -----------------------------------------------------------------------------
// 独立运行：只依赖 sram_sync.v，不 include / 不例化任何其他模块。
//   iverilog -o sim.out sram_sync.v tb_sram_sync.v && vvp sim.out
//
// 激励在 negedge 驱动，posedge 由 DUT 采样，在下一个 negedge 检查 rdata。
// 这样 rdata 的 1 拍读延迟被显式体现。
// 覆盖：写后读回 / 连续写不同地址再连续读 / we=0 时保持 / 边界地址 0 与 MAX
//       以及读延迟与同地址读写的 read-first 行为。
// =============================================================================
`timescale 1ns/1ps

module tb_sram_sync;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 10;
    localparam DEPTH      = 1 << ADDR_WIDTH;
    localparam ADDR_MAX   = DEPTH - 1;

    reg                      clk   = 1'b0;
    reg                      rst;
    reg                      we;
    reg  [ADDR_WIDTH-1:0]    addr;
    reg  [DATA_WIDTH-1:0]    wdata;
    wire [DATA_WIDTH-1:0]    rdata;

    integer tests;
    integer errors;

    sram_sync #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .clk   (clk),
        .rst   (rst),
        .we    (we),
        .addr  (addr),
        .wdata (wdata),
        .rdata (rdata)
    );

    always #5 clk = ~clk;

    // 检查结果并逐行打印 PASS / FAIL
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

    // step(we, addr, wdata)：驱动一个完整时钟周期，返回时 rdata 已有效
    task step;
        input                   i_we;
        input [ADDR_WIDTH-1:0]  i_addr;
        input [DATA_WIDTH-1:0]  i_wdata;
        begin
            @(negedge clk);
            we    = i_we;
            addr  = i_addr;
            wdata = i_wdata;
            @(negedge clk);
        end
    endtask

    initial begin
        tests  = 0;
        errors = 0;
        rst    = 1'b1;
        we     = 1'b0;
        addr   = {ADDR_WIDTH{1'b0}};
        wdata  = {DATA_WIDTH{1'b0}};

        repeat (2) @(negedge clk);
        rst = 1'b0;
        check("TC01 sync reset clears rdata", rdata, 32'h0000_0000);

        // ---- 写入后读回相同数据 ----
        step(1'b1, 10'h055, 32'hA5A5_5A5A);
        step(1'b0, 10'h055, 32'h0000_0000);
        check("TC02 write then read back", rdata, 32'hA5A5_5A5A);

        // ---- 连续写不同地址，再连续读：验证地址译码 ----
        step(1'b1, 10'h010, 32'h1111_1111);
        step(1'b1, 10'h011, 32'h2222_2222);
        step(1'b1, 10'h012, 32'h3333_3333);
        step(1'b1, 10'h013, 32'h4444_4444);
        step(1'b0, 10'h010, 32'h0);
        check("TC03 addr decode 0x010", rdata, 32'h1111_1111);
        step(1'b0, 10'h011, 32'h0);
        check("TC04 addr decode 0x011", rdata, 32'h2222_2222);
        step(1'b0, 10'h012, 32'h0);
        check("TC05 addr decode 0x012", rdata, 32'h3333_3333);
        step(1'b0, 10'h013, 32'h0);
        check("TC06 addr decode 0x013", rdata, 32'h4444_4444);

        // ---- 边界地址 0 与最大值 ----
        step(1'b1, 10'h000, 32'hFFFF_FFFF);
        step(1'b0, 10'h000, 32'h0);
        check("TC07 boundary addr 0", rdata, 32'hFFFF_FFFF);
        step(1'b1, ADDR_MAX, 32'h0000_0001);
        step(1'b0, ADDR_MAX, 32'h0);
        check("TC08 boundary addr MAX", rdata, 32'h0000_0001);

        // ---- we = 0 时读数据保持不变，且不会改写阵列 ----
        step(1'b1, 10'h020, 32'hCAFE_BABE);
        step(1'b0, 10'h020, 32'hDEAD_DEAD);
        check("TC09 we=0 read hold cycle 1", rdata, 32'hCAFE_BABE);
        step(1'b0, 10'h020, 32'hDEAD_DEAD);
        check("TC10 we=0 read hold cycle 2", rdata, 32'hCAFE_BABE);
        step(1'b0, 10'h020, 32'hDEAD_DEAD);
        check("TC11 we=0 read hold cycle 3", rdata, 32'hCAFE_BABE);

        // ---- 读延迟 1 拍：地址改变后，要等 posedge rdata 才更新 ----
        @(negedge clk);
        we    = 1'b0;
        addr  = 10'h010;
        wdata = 32'h0;
        check("TC12 read latency, before posedge", rdata, 32'hCAFE_BABE);
        @(posedge clk);
        #1;
        check("TC13 read latency, after posedge", rdata, 32'h1111_1111);

        // ---- 同拍读写同一地址：read-first ----
        step(1'b1, 10'h030, 32'h0BAD_F00D);
        step(1'b1, 10'h030, 32'h1234_5678);
        check("TC14 same addr write/read is read-first", rdata, 32'h0BAD_F00D);
        step(1'b0, 10'h030, 32'h0);
        check("TC15 new value visible at next read", rdata, 32'h1234_5678);

        #20;
        $display("------------------------------------------------------------");
        if (errors == 0)
            $display("[SUMMARY] tb_sram_sync : %0d PASS, 0 FAIL  => ALL PASS", tests);
        else
            $display("[SUMMARY] tb_sram_sync : %0d checks, %0d FAIL  => TEST FAIL",
                     tests, errors);
        $finish;
    end

    // 看门狗，防止激励卡死
    initial begin
        #20000;
        $display("[TIMEOUT] tb_sram_sync did not finish");
        $finish;
    end

endmodule
