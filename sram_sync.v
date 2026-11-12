`timescale 1ns/1ps

// =============================================================================
// sram_sync.v  --  single-port synchronous SRAM, Verilog-2001
// -----------------------------------------------------------------------------
// 功能
//   单端口同步静态存储器。读、写都在 clk 上升沿采样，输出 rdata 为寄存器。
//   阵列按字寻址：DEPTH = 2^ADDR_WIDTH 个 DATA_WIDTH 位的字。
//
// 参数
//   DATA_WIDTH  数据位宽，默认 32
//   ADDR_WIDTH  地址位宽，默认 10（DEPTH = 1024 字）
//
// 端口
//   clk    输入，时钟，上升沿有效
//   rst    输入，同步复位，高有效
//   we     输入，写使能；1 = 本拍把 wdata 写入 addr
//   addr   输入，读写共用地址，本拍采样
//   wdata  输入，写数据，本拍采样
//   rdata  输出，读数据寄存器
//
// 时序假设
//   - 写延迟 1 拍：posedge T 采样 we/addr/wdata，T 之后 mem[addr] 已是新值，
//     T+1 拍及以后对该地址发起的读可见新值。
//   - 读延迟 1 拍：posedge T 采样 addr，rdata 在 T 之后（T -> T+1 这一周期）
//     有效；外部应在 posedge 之后（例如 negedge）采样 rdata。
//   - 同一拍对同一地址读写（we = 1）：read-first。rdata 输出写入前的旧值，
//     写入的新值要到下一拍再读才可见。
//   - we = 0 时只发起读，阵列内容不变。
//
// 复位方式
//   同步复位、高有效。rst = 1 的上升沿只把 rdata 清 0；存储阵列 mem
//   不做复位、不做上电初始化（与真实 SRAM 一致，上电内容未知）。
//   因此测试必须先写后读，不得依赖复位后的存储内容。
//
// 实现说明
//   写阵列与锁存读数据合并在同一个 always @(posedge clk) 中，只有一份
//   采样逻辑；全部采用非阻塞赋值，天然得到 read-first 语义；rdata 在
//   if/else 的每个分支都有赋值，不推断 latch。
// =============================================================================

module sram_sync #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10
)(
    input                        clk,
    input                        rst,
    input                        we,
    input  [ADDR_WIDTH-1:0]      addr,
    input  [DATA_WIDTH-1:0]      wdata,
    output reg [DATA_WIDTH-1:0]  rdata
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (rst) begin
            rdata <= {DATA_WIDTH{1'b0}};
        end else begin
            rdata <= mem[addr];            // 非阻塞：取写入前的旧值
            if (we) begin
                mem[addr] <= wdata;
            end
        end
    end

endmodule
