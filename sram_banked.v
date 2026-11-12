`timescale 1ns/1ps

// =============================================================================
// sram_banked.v  --  banked synchronous SRAM, Verilog-2001
// -----------------------------------------------------------------------------
// 功能
//   把阵列按低位交织划分成 NUM_BANKS 个 bank，每个 bank 由 generate 生成的
//   独立时序块服务。两端口（A: IF 取指，B: MEM 访存）同拍访问不同 bank 时
//   并行执行；访问同一 bank 时按下面定义的优先级仲裁。
//
// 参数
//   DATA_WIDTH  数据位宽，默认 32
//   ADDR_WIDTH  地址位宽，默认 10（DEPTH = 1024 字）
//   NUM_BANKS   bank 数，默认 4。必须是 2 的幂且 >= 2，并且 NUM_BANKS <= DEPTH。
//               约束在下面的 initial 块中做检查并打印错误。
//
// 端口
//   clk                  输入，时钟，上升沿有效
//   rst                  输入，同步复位，高有效
//   we_a   / we_b        输入，端口 A / B 写使能
//   addr_a / addr_b      输入，端口 A / B 地址
//   wdata_a / wdata_b    输入，端口 A / B 写数据
//   rdata_a / rdata_b    输出，端口 A / B 读数据寄存器
//
// bank 选择规则（低位交织 / low-order interleaving）
//   BANK_SEL_WIDTH = clog2(NUM_BANKS)
//   bank_sel  = addr[BANK_SEL_WIDTH-1 : 0]        （地址低位）
//   bank_addr = addr[ADDR_WIDTH-1 : BANK_SEL_WIDTH]（bank 内地址）
//   即全局地址 addr = {bank_addr, bank_sel}；bank g 占据所有满足
//   (addr % NUM_BANKS) == g 的地址。因此 addr、addr+1、addr+2... 依次落在
//   bank 0/1/2/3/0/1...，连续地址天然跨 bank，可并行；而 addr 与
//   addr + NUM_BANKS 落在同一 bank 的不同 bank_addr。
//   例：NUM_BANKS=4, ADDR_WIDTH=10 时，0x100/0x101/0x102/0x103 分别在
//   bank 0/1/2/3；0x100/0x104/0x108 都在 bank 0。
//
// 时序假设
//   - 读延迟 1 拍、写延迟 1 拍，与 sram_sync / sram_dp 一致：posedge T 采样，
//     rdata 在 T -> T+1 周期有效，写入值在 T+1 拍及以后的读可见。
//   - 读为 read-first：同拍写某地址时，读端口返回写入前的旧值。
//   - 两端口的读不受 bank 仲裁限制，同 bank 双读也正常返回。
//
// bank 冲突与优先级（明确定义）
//   1. 同拍两端口命中不同 bank：两个写各自落到不同的 bank 时序块，并行生效。
//   2. 同拍两端口写同一 bank（即使 bank_addr 不同，也按 bank 粒度判冲突）：
//      端口 A 优先，A 的写执行，B 的写被丢弃。
//   3. 同拍一端口写、另一端口读同一 bank（含同一地址）：读正常工作，
//      返回写前旧值；不视为需要阻塞的冲突。
//   4. 同拍两端口读同一 bank：都正常返回旧值，无冲突。
//
// 复位方式
//   同步复位、高有效。rst = 1 的上升沿只把 rdata_a / rdata_b 清 0；
//   阵列 mem 不做复位、不做上电初始化。测试必须先写后读。
//
// 实现说明
//   - mem 为一维数组，按上面的地址划分规则在逻辑上分成 NUM_BANKS 个互不
//     重叠的 bank 地址集合；bank 命中时直接用全局 addr 作为阵列下标。
//   - 写逻辑只有一份模板，由 generate for 复制 NUM_BANKS 份，bank 数改参数
//     即可，不存在手工复制粘贴的重复代码。
//   - 读逻辑只有一份（顶层输出寄存器块），组合地址译码用 always @(*) 且
//     所有分支全赋值，输出寄存器在 if/else 每个分支都赋值，不推断 latch。
// =============================================================================

module sram_banked #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10,
    parameter NUM_BANKS  = 4
)(
    input                        clk,
    input                        rst,
    input                        we_a,
    input                        we_b,
    input  [ADDR_WIDTH-1:0]      addr_a,
    input  [ADDR_WIDTH-1:0]      addr_b,
    input  [DATA_WIDTH-1:0]      wdata_a,
    input  [DATA_WIDTH-1:0]      wdata_b,
    output reg [DATA_WIDTH-1:0]  rdata_a,
    output reg [DATA_WIDTH-1:0]  rdata_b
);

    // Verilog-2001 常量函数，替代 Verilog-2005 才有的 $clog2
    function integer clog2;
        input integer value;
        integer v;
        begin
            v     = value - 1;
            clog2 = 0;
            while (v > 0) begin
                v     = v >> 1;
                clog2 = clog2 + 1;
            end
        end
    endfunction

    localparam BANK_SEL_WIDTH  = clog2(NUM_BANKS);
    localparam BANK_ADDR_WIDTH = ADDR_WIDTH - BANK_SEL_WIDTH;
    localparam BANK_DEPTH      = (32'd1 << BANK_ADDR_WIDTH); // 每个 bank 的字数
    localparam DEPTH           = (32'd1 << ADDR_WIDTH);      // 阵列总字数

    // 参数合法性检查（仅仿真时提示，不参与综合逻辑）
    // synthesis translate_off
    initial begin
        if ((NUM_BANKS < 2) || (NUM_BANKS > DEPTH) ||
            ((NUM_BANKS & (NUM_BANKS - 1)) != 0)) begin
            $display("[ERROR] sram_banked: NUM_BANKS must be a power of 2, >= 2 and <= 2^ADDR_WIDTH");
        end
    end
    // synthesis translate_on

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // ---- 组合地址译码：地址低位选 bank ----
    reg [BANK_SEL_WIDTH-1:0]  bank_a;
    reg [BANK_SEL_WIDTH-1:0]  bank_b;
    reg [BANK_ADDR_WIDTH-1:0] bank_addr_a;
    reg [BANK_ADDR_WIDTH-1:0] bank_addr_b;

    always @(*) begin
        bank_a      = addr_a[BANK_SEL_WIDTH-1:0];
        bank_b      = addr_b[BANK_SEL_WIDTH-1:0];
        bank_addr_a = addr_a[ADDR_WIDTH-1:BANK_SEL_WIDTH];
        bank_addr_b = addr_b[ADDR_WIDTH-1:BANK_SEL_WIDTH];
    end

    // ---- 每个 bank 一个独立的写时序块；同一模板由 generate 展开 ----
    genvar g;
    generate
        for (g = 0; g < NUM_BANKS; g = g + 1) begin : bank
            wire hit_a;
            wire hit_b;

            assign hit_a = (bank_a == g);
            assign hit_b = (bank_b == g);

            always @(posedge clk) begin
                // A 命中本 bank：执行写
                if (we_a && hit_a) begin
                    mem[addr_a] <= wdata_a;
                end
                // B 命中本 bank，且 A 没有同时在写本 bank：才执行写（A 优先）
                if (we_b && hit_b && !(we_a && hit_a)) begin
                    mem[addr_b] <= wdata_b;
                end
            end
        end
    endgenerate

    // ---- 顶层同步读：只有一份输出寄存器逻辑，read-first，1 拍延迟 ----
    always @(posedge clk) begin
        if (rst) begin
            rdata_a <= {DATA_WIDTH{1'b0}};
            rdata_b <= {DATA_WIDTH{1'b0}};
        end else begin
            rdata_a <= mem[addr_a];
            rdata_b <= mem[addr_b];
        end
    end

endmodule
