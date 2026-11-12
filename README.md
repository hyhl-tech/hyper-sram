# Hyper SRAM

Hyper Core 的片上存储子系统。用 Verilog 实现**同步 SRAM**、**双端口 SRAM** 和 **banked SRAM**，用于替换 Hyper Core 中理想化的 `imem` / `dmem`，让 CPU 第一次面对真实的存储器延迟。

项目由**华阳互联学生团队**开发，用 [Icarus Verilog](http://iverilog.icarus.com/) 仿真验证。

## 当前状态

| 模块 | 状态 |
|---|---|
| 同步 SRAM（同步读、同步写） | 🚧 开发中 |
| 双端口 SRAM（IF/MEM 分离） | ⬜ 未开始 |
| Banked SRAM（多 bank 并行） | ⬜ 未开始 |
| 6T SRAM 单元（门级，学习用） | ⬜ 未开始 |

## 为什么做这个

Hyper Core 目前的 `imem` 和 `dmem` 是行为级模型：读是组合逻辑，地址一变数据立刻出来，没有延迟。这在仿真里成立，在真实硬件里不成立。真实的 SRAM 读数据需要一个时钟周期，写数据也需要一个时钟周期。

这个仓库的目标是：把 Hyper Core 的存储器从“理想化”换成“同步 SRAM”，看流水线怎么应对存储器延迟。这会逼我们重新思考 IF 阶段的取指、MEM 阶段的访存、stall 逻辑和 valid 位的对齐。
## 当前状态

同步 SRAM 的 RTL 和 testbench 正在开发中。目标是：读和写都在时钟沿发生，`rdata` 在下一个周期有效，用 `iverilog` 跑出 `PASS`。跑通后会把 RTL、testbench、仿真日志一起提交。

双端口 SRAM、banked SRAM、6T SRAM 单元尚未开始。
