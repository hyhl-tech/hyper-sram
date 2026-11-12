`timescale 1ns/1ps

// =============================================================================
// sram_dp.v  --  true dual-port synchronous SRAM, Verilog-2001
// -----------------------------------------------------------------------------
// 功能
//   真双端口同步静态存储器。端口 A 供 IF 取指，端口 B 供 MEM 访存。
//   两组 we/addr/wdata/rdata 完全独立、同拍并行，不需要仲裁总线或分时复用。
//   两端口共享同一个物理阵列（A 写入的数据 B 可读，反之亦然）。
//
// 参数
//   DATA_WIDTH  数据位宽，默认 32
//   ADDR_WIDTH  地址位宽，默认 10（DEPTH = 1024 字）
//
// 端口
//   clk                  输入，时钟，两端口同域，上升沿有效
//   rst                  输入，同步复位，高有效
//   we_a   / we_b        输入，端口 A / B 写使能
//   addr_a / addr_b      输入，端口 A / B 地址
//   wdata_a / wdata_b    输入，端口 A / B 写数据
//   rdata_a / rdata_b    输出，端口 A / B 读数据寄存器
//
// 时序假设
//   - 读延迟 1 拍、写延迟 1 拍，与 sram_sync 相同：posedge T 采样地址/数据，
//     rdata 在 T -> T+1 周期有效；写入值在 T+1 拍及以后的读可见。
//   - 两端口始终各自发起读，读不会互相阻塞；读数据为写入前的旧值（read-first）。
//
// 冲突优先级（明确定义）
//   1. 两端口同拍访问不同地址：读写互不影响，两个写都生效。
//   2. 两端口同拍写同一地址：端口 A 优先，A 的 wdata_a 写入，
//      端口 B 的写被丢弃（同拍 rdata_a/rdata_b 仍输出旧值）。
//   3. 一端口写、另一端口读同一地址：读端口返回写入前的旧值（read-first），
//      新值下一拍可见。
//   4. 两端口同拍读同一地址：两者都返回同一旧值，无冲突。
//
// 复位方式
//   同步复位、高有效。rst = 1 的上升沿只把 rdata_a / rdata_b 清 0；
//   存储阵列 mem 不做复位、不做上电初始化。测试必须先写后读。
//
// 实现说明
//   两个端口的写放在同一个 always @(posedge clk) 中（同一阵列必须单块驱动），
//   B 端口的写条件里显式排除 "A 也在写同一地址"，从而落实 A 优先。
//   rdata_a / rdata_b 在所有分支都有赋值，不推断 latch。
// =============================================================================

module sram_dp #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10
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

    localparam DEPTH = 1 << ADDR_WIDTH;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (rst) begin
            rdata_a <= {DATA_WIDTH{1'b0}};
            rdata_b <= {DATA_WIDTH{1'b0}};
        end else begin
            // 两端口独立同步读，read-first
            rdata_a <= mem[addr_a];
            rdata_b <= mem[addr_b];

            // 写：A 优先；只有 A 未在同一地址写时，B 的写才生效
            if (we_a) begin
                mem[addr_a] <= wdata_a;
            end
            if (we_b && !(we_a && (addr_a == addr_b))) begin
                mem[addr_b] <= wdata_b;
            end
        end
    end

endmodule
