// =============================================================================
// tb_sram_banked.v  --  self-contained testbench for sram_banked.v
// -----------------------------------------------------------------------------
// 独立运行：只依赖 sram_banked.v，不 include / 不例化任何其他模块。
//   iverilog -o sim.out sram_banked.v tb_sram_banked.v && vvp sim.out
//
// cyc 参数顺序：we_a, addr_a, wdata_a, we_b, addr_b, wdata_b
// 配置：DATA_WIDTH=32, ADDR_WIDTH=10, NUM_BANKS=4
//   bank_sel = addr[1:0]，故 0x100/0x101/0x102/0x103 落在 bank 0/1/2/3，
//   0x100/0x104/0x108 同属 bank 0，0x110/0x114 同属 bank 0。
//
// 覆盖：写后读回 / 边界地址 / we=0 保持 / 连续地址跨 bank 并行访问 /
//       同一 bank 内连续访问 / 同 bank 双读 / bank 冲突 A 优先 /
//       同 bank 一写一读 read-first / 不同 bank 双写 / 读延迟。
// =============================================================================
`timescale 1ns/1ps

module tb_sram_banked;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 10;
    localparam NUM_BANKS  = 4;
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

    sram_banked #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .NUM_BANKS  (NUM_BANKS)
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

        // ---- 写后读回；两端口共享阵列 ----
        cyc(1'b1, 10'h100, 32'h0000_0100, 1'b0, 10'h000, 32'h0);
        cyc(1'b0, 10'h100, 32'h0,        1'b0, 10'h000, 32'h0);
        check("TC03 port A write then read back", rdata_a, 32'h0000_0100);
        cyc(1'b0, 10'h000, 32'h0,        1'b1, 10'h101, 32'h0000_0101);
        cyc(1'b0, 10'h101, 32'h0,        1'b0, 10'h000, 32'h0);
        check("TC04 port A reads what port B wrote", rdata_a, 32'h0000_0101);

        // ---- 连续地址跨 bank：0x100..0x103 落在 bank 0/1/2/3，同拍并行写 ----
        cyc(1'b1, 10'h100, 32'hAAAA_0100, 1'b1, 10'h101, 32'hBBBB_0101);
        cyc(1'b0, 10'h100, 32'h0,        1'b0, 10'h101, 32'h0);
        check("TC05 cross-bank 0x100/0x101, port A", rdata_a, 32'hAAAA_0100);
        check("TC06 cross-bank 0x100/0x101, port B", rdata_b, 32'hBBBB_0101);
        cyc(1'b1, 10'h102, 32'hCCCC_0102, 1'b1, 10'h103, 32'hDDDD_0103);
        cyc(1'b0, 10'h102, 32'h0,        1'b0, 10'h103, 32'h0);
        check("TC07 cross-bank 0x102/0x103, port A", rdata_a, 32'hCCCC_0102);
        check("TC08 cross-bank 0x102/0x103, port B", rdata_b, 32'hDDDD_0103);

        // ---- 同一 bank 内连续访问：0x100/0x104/0x108 都属于 bank 0 ----
        cyc(1'b1, 10'h104, 32'h1111_0004, 1'b0, 10'h000, 32'h0);
        cyc(1'b1, 10'h108, 32'h2222_0008, 1'b0, 10'h000, 32'h0);
        cyc(1'b0, 10'h100, 32'h0,        1'b0, 10'h104, 32'h0);
        check("TC09 same-bank addr 0x100 unchanged", rdata_a, 32'hAAAA_0100);
        check("TC10 same-bank addr 0x104 decoded", rdata_b, 32'h1111_0004);
        // 同 bank 双读：读不参与仲裁，两端口都应正常返回
        cyc(1'b0, 10'h108, 32'h0,        1'b0, 10'h108, 32'h0);
        check("TC11 same-bank dual read, port A", rdata_a, 32'h2222_0008);
        check("TC12 same-bank dual read, port B", rdata_b, 32'h2222_0008);

        // ---- bank 冲突：0x110 与 0x114 同属 bank 0，同拍双写 -> A 优先 ----
        cyc(1'b1, 10'h114, 32'h0BAD_0BAD, 1'b0, 10'h000, 32'h0); // 预写旧值
        cyc(1'b1, 10'h110, 32'hA110_0000, 1'b1, 10'h114, 32'hB114_0000);
        cyc(1'b0, 10'h110, 32'h0,        1'b0, 10'h114, 32'h0);
        check("TC13 bank conflict, port A write kept", rdata_a, 32'hA110_0000);
        check("TC14 bank conflict, port B write dropped", rdata_b, 32'h0BAD_0BAD);

        // ---- 同 bank 一写一读同一地址：read-first ----
        cyc(1'b1, 10'h120, 32'h0DAD_0120, 1'b0, 10'h000, 32'h0);
        cyc(1'b1, 10'h120, 32'h1234_0120, 1'b0, 10'h120, 32'h0);
        check("TC15 same-bank write/read is read-first", rdata_b, 32'h0DAD_0120);
        cyc(1'b0, 10'h000, 32'h0,        1'b0, 10'h120, 32'h0);
        check("TC16 new value visible at next read", rdata_b, 32'h1234_0120);

        // ---- 不同 bank 同拍双写：0x130(bank0) / 0x131(bank1) ----
        cyc(1'b1, 10'h130, 32'hAAAA_0130, 1'b1, 10'h131, 32'hBBBB_0131);
        cyc(1'b0, 10'h130, 32'h0,        1'b0, 10'h131, 32'h0);
        check("TC17 different-bank write, port A", rdata_a, 32'hAAAA_0130);
        check("TC18 different-bank write, port B", rdata_b, 32'hBBBB_0131);

        // ---- 边界地址 0(bank0) 与 0x3FF(bank3)，不同 bank 可同拍写 ----
        cyc(1'b1, 10'h000, 32'hFFFF_FFFF, 1'b1, ADDR_MAX, 32'h0000_0001);
        cyc(1'b0, 10'h000, 32'h0,        1'b0, ADDR_MAX, 32'h0);
        check("TC19 boundary addr 0", rdata_a, 32'hFFFF_FFFF);
        check("TC20 boundary addr MAX", rdata_b, 32'h0000_0001);

        // ---- we = 0：两端口读数据保持不变，wdata 不改写阵列 ----
        cyc(1'b1, 10'h140, 32'hCAFE_BABE, 1'b0, 10'h000, 32'h0);
        cyc(1'b0, 10'h140, 32'hDEAD_DEAD, 1'b0, 10'h140, 32'hDEAD_DEAD);
        check("TC21 we=0 hold on port A", rdata_a, 32'hCAFE_BABE);
        check("TC22 we=0 hold on port B", rdata_b, 32'hCAFE_BABE);
        cyc(1'b0, 10'h140, 32'hDEAD_DEAD, 1'b0, 10'h140, 32'hDEAD_DEAD);
        check("TC23 we=0 hold, second cycle", rdata_a, 32'hCAFE_BABE);

        // ---- 读延迟 1 拍：地址改变后要等 posedge rdata 才更新 ----
        @(negedge clk);
        we_a    = 1'b0;  addr_a  = 10'h100; wdata_a = 32'h0;
        we_b    = 1'b0;  addr_b  = 10'h100; wdata_b = 32'h0;
        check("TC24 read latency, before posedge", rdata_a, 32'hCAFE_BABE);
        @(posedge clk);
        #1;
        check("TC25 read latency, after posedge", rdata_a, 32'hAAAA_0100);

        #20;
        $display("------------------------------------------------------------");
        if (errors == 0)
            $display("[SUMMARY] tb_sram_banked : %0d PASS, 0 FAIL  => ALL PASS", tests);
        else
            $display("[SUMMARY] tb_sram_banked : %0d checks, %0d FAIL  => TEST FAIL",
                     tests, errors);
        $finish;
    end

    initial begin
        #20000;
        $display("[TIMEOUT] tb_sram_banked did not finish");
        $finish;
    end

endmodule
