# Hyper SRAM

Hyper Core CPU 的片上存储子系统，Verilog-2001 实现，包含三个模块：

| 模块 | 文件 | 说明 |
| --- | --- | --- |
| `sram_sync` | `sram_sync.v` | 单端口同步 SRAM，同步读、同步写 |
| `sram_dp` | `sram_dp.v` | 真双端口同步 SRAM，A 给 IF 取指、B 给 MEM 访存 |
| `sram_banked` | `sram_banked.v` | 低位交织分 bank，两端口同拍可访问不同 bank |

三个模块各有一个独立 testbench，均只依赖自己的 RTL 文件。

## 文件清单

```
LICENSE            已存在，本次未改动
.gitignore         忽略 iverilog 编译产物、波形、临时文件
README.md          本文件
sram_sync.v        tb_sram_sync.v
sram_dp.v          tb_sram_dp.v
sram_banked.v      tb_sram_banked.v
sim.out            iverilog 编译产物（被 .gitignore 忽略）
```

## 参数与端口

| 参数 | 默认值 | 适用模块 |
| --- | --- | --- |
| `DATA_WIDTH` | 32 | 全部 |
| `ADDR_WIDTH` | 10（1024 字） | 全部 |
| `NUM_BANKS` | 4 | 仅 `sram_banked` |

信号命名：`clk`、`rst`、`we`、`addr`、`wdata`、`rdata`；双端口与 banked 版本用
`we_a/we_b`、`addr_a/addr_b`、`wdata_a/wdata_b`、`rdata_a/rdata_b`。
`banked` 的 bank 选择不使用独立引脚，由地址低位译码（`bank_sel`）。

## 时序与行为约定

- 三个模块统一：**读延迟 1 拍、写延迟 1 拍**。时钟上升沿采样地址/写数据/写使能，
  `rdata` 在该上升沿之后（即下一拍）有效；写入值在之后发起的读可见。
- 同拍读写同一地址为 **read-first**：读端口返回写入前的旧值，新值下一拍可见。
- `we = 0` 时仍发起读，阵列内容不变；`wdata` 被忽略。
- **复位方式**：同步复位、高有效。仅把 `rdata`（或 `rdata_a/rdata_b`）清 0，
  存储阵列不复位、不做上电初始化，内容未知。测试必须先写后读。
- 组合逻辑用 `always @(*)`（全分支赋值），时序逻辑用 `always @(posedge clk)`，
  输出寄存器在每个分支都有赋值，不推断 latch。未使用 `logic`/`always_ff`/`always_comb`。

### 双端口冲突优先级（`sram_dp`）

1. 两端口同拍访问不同地址：读写互不影响，两个写都生效。
2. 两端口同拍写同一地址：**端口 A 优先**，A 的 `wdata_a` 写入，B 的写被丢弃。
3. 一端口写、另一端口读同一地址：读返回旧值（read-first）。
4. 两端口同拍读同一地址：都返回同一旧值，无冲突。

### bank 选择规则与冲突优先级（`sram_banked`）

- `BANK_SEL_WIDTH = clog2(NUM_BANKS)`，用 Verilog-2001 常量函数实现（未用 `$clog2`）。
- **低位交织**：`bank_sel = addr[BANK_SEL_WIDTH-1:0]`（地址低位），
  `bank_addr = addr[ADDR_WIDTH-1:BANK_SEL_WIDTH]`（bank 内地址），
  即 `addr = {bank_addr, bank_sel}`。bank g 占据所有 `(addr % NUM_BANKS) == g` 的地址。
  因此 `addr`、`addr+1`、`addr+2...` 依次落在不同 bank，连续地址可并行；
  而 `addr` 与 `addr + NUM_BANKS` 落在同一 bank。
  `NUM_BANKS = 4, ADDR_WIDTH = 10` 时：`0x100/0x101/0x102/0x103` 在 bank 0/1/2/3，
  `0x100/0x104/0x108` 都在 bank 0。
- 每个 bank 由 `generate for` 展开的独立写时序块服务，写逻辑只有一份模板；
  bank 数改 `NUM_BANKS` 即可。约束：`NUM_BANKS` 为 2 的幂、`>= 2`、`<= 2^ADDR_WIDTH`
  （RTL 内有参数检查 initial 块）。
- 读不受 bank 仲裁限制，同 bank 双读也正常返回。
- **bank 冲突**：同拍两端口写同一 bank（按 bank 粒度判定，即使 bank_addr 不同）
  时 **端口 A 优先**，A 的写执行，B 的写被丢弃；同拍访问不同 bank 则两个写并行生效。
- 一端口写、另一端口读同一 bank（含同一地址）：读正常，返回写前旧值。

## 仿真环境

本机 Icarus Verilog 位于 `C:\iverilog\bin`，未加入系统 PATH：

```
Icarus Verilog version 12.0 (devel) (s20150603-1539-g2693dd32b)
```

Git Bash 下先执行（PowerShell 用 `$env:PATH = "C:\iverilog\bin;$env:PATH"`）：

```
export PATH="/c/iverilog/bin:$PATH"
```

三组命令彼此独立，共用 `sim.out` 输出名，按顺序执行即可：

```
iverilog -o sim.out sram_sync.v   tb_sram_sync.v   && vvp sim.out
iverilog -o sim.out sram_dp.v     tb_sram_dp.v     && vvp sim.out
iverilog -o sim.out sram_banked.v tb_sram_banked.v && vvp sim.out
```

另外用 `iverilog -g2001 -Wall -t null` 对三组文件分别做了严格 Verilog-2001 语法检查，
退出码均为 0，无警告。

---

## 第一步：同步 SRAM `sram_sync`

命令：

```
iverilog -o sim.out sram_sync.v tb_sram_sync.v && vvp sim.out
```

覆盖：复位清零、写后读回、连续写 4 个不同地址再连续读（地址译码）、
`we=0` 时连续 3 拍读数据保持、边界地址 0 / `0x3FF`、读延迟 1 拍、
同地址读写 read-first。共 15 项检查。

### 预期终端输出（逐行）

```
[PASS] TC01 sync reset clears rdata data=0x00000000
[PASS] TC02 write then read back data=0xa5a55a5a
[PASS] TC03 addr decode 0x010 data=0x11111111
[PASS] TC04 addr decode 0x011 data=0x22222222
[PASS] TC05 addr decode 0x012 data=0x33333333
[PASS] TC06 addr decode 0x013 data=0x44444444
[PASS] TC07 boundary addr 0 data=0xffffffff
[PASS] TC08 boundary addr MAX data=0x00000001
[PASS] TC09 we=0 read hold cycle 1 data=0xcafebabe
[PASS] TC10 we=0 read hold cycle 2 data=0xcafebabe
[PASS] TC11 we=0 read hold cycle 3 data=0xcafebabe
[PASS] TC12 read latency, before posedge data=0xcafebabe
[PASS] TC13 read latency, after posedge data=0x11111111
[PASS] TC14 same addr write/read is read-first data=0x0badf00d
[PASS] TC15 new value visible at next read data=0x12345678
------------------------------------------------------------
[SUMMARY] tb_sram_sync : 15 PASS, 0 FAIL  => ALL PASS
```

### 真实仿真日志

```
[PASS] TC01 sync reset clears rdata data=0x00000000
[PASS] TC02 write then read back data=0xa5a55a5a
[PASS] TC03 addr decode 0x010 data=0x11111111
[PASS] TC04 addr decode 0x011 data=0x22222222
[PASS] TC05 addr decode 0x012 data=0x33333333
[PASS] TC06 addr decode 0x013 data=0x44444444
[PASS] TC07 boundary addr 0 data=0xffffffff
[PASS] TC08 boundary addr MAX data=0x00000001
[PASS] TC09 we=0 read hold cycle 1 data=0xcafebabe
[PASS] TC10 we=0 read hold cycle 2 data=0xcafebabe
[PASS] TC11 we=0 read hold cycle 3 data=0xcafebabe
[PASS] TC12 read latency, before posedge data=0xcafebabe
[PASS] TC13 read latency, after posedge data=0x11111111
[PASS] TC14 same addr write/read is read-first data=0x0badf00d
[PASS] TC15 new value visible at next read data=0x12345678
------------------------------------------------------------
[SUMMARY] tb_sram_sync : 15 PASS, 0 FAIL  => ALL PASS
tb_sram_sync.v:147: $finish called at 470000 (1ps)
```

最后一行是 Icarus 在 `$finish` 时自动打印的，不属于 testbench 的 PASS 输出。

---

## 第二步：双端口 SRAM `sram_dp`

命令：

```
iverilog -o sim.out sram_dp.v tb_sram_dp.v && vvp sim.out
```

覆盖：复位清零、A/B 各自写后读回、A 写 B 读与 B 写 A 读（共享阵列）、
连续写 4 个不同地址再连续读、边界地址 0 / `0x3FF`、`we=0` 保持、
两端口同时读不同地址、一端口写另一端口读不同/相同地址、写冲突 A 优先、
不同地址同拍双写。共 25 项检查。

### 预期终端输出（逐行）

```
[PASS] TC01 sync reset clears rdata_a data=0x00000000
[PASS] TC02 sync reset clears rdata_b data=0x00000000
[PASS] TC03 port A write then read back data=0xaaaa0000
[PASS] TC04 port B reads what port A wrote data=0xbbbb0000
[PASS] TC05 port A reads what port B wrote data=0xcccc0000
[PASS] TC06 addr decode 0x010 data=0x11111111
[PASS] TC07 addr decode 0x011 data=0x22222222
[PASS] TC08 addr decode 0x012 data=0x33333333
[PASS] TC09 addr decode 0x013 data=0x44444444
[PASS] TC10 boundary addr 0 data=0xffffffff
[PASS] TC11 boundary addr MAX data=0x00000001
[PASS] TC12 we=0 hold on port A data=0xcafebabe
[PASS] TC13 we=0 hold on port B data=0xcafebabe
[PASS] TC14 we=0 hold, second cycle data=0xcafebabe
[PASS] TC15 simultaneous read A at 0x010 data=0x11111111
[PASS] TC16 simultaneous read B at 0x011 data=0x22222222
[PASS] TC17 B reads while A writes elsewhere data=0x33333333
[PASS] TC18 A write visible at next read data=0x0dad0000
[PASS] TC19 same addr write/read is read-first data=0x0badf00d
[PASS] TC20 new value visible at next read data=0x12345678
[PASS] TC21 conflict cycle is read-first data=0x0abcdef0
[PASS] TC22 conflict result, port A wins data=0xaaaa5555
[PASS] TC23 conflict result, port B write dropped data=0xaaaa5555
[PASS] TC24 distinct addr write, A effective data=0x77770000
[PASS] TC25 distinct addr write, B effective data=0x88880000
------------------------------------------------------------
[SUMMARY] tb_sram_dp : 25 PASS, 0 FAIL  => ALL PASS
```

### 真实仿真日志

```
[PASS] TC01 sync reset clears rdata_a data=0x00000000
[PASS] TC02 sync reset clears rdata_b data=0x00000000
[PASS] TC03 port A write then read back data=0xaaaa0000
[PASS] TC04 port B reads what port A wrote data=0xbbbb0000
[PASS] TC05 port A reads what port B wrote data=0xcccc0000
[PASS] TC06 addr decode 0x010 data=0x11111111
[PASS] TC07 addr decode 0x011 data=0x22222222
[PASS] TC08 addr decode 0x012 data=0x33333333
[PASS] TC09 addr decode 0x013 data=0x44444444
[PASS] TC10 boundary addr 0 data=0xffffffff
[PASS] TC11 boundary addr MAX data=0x00000001
[PASS] TC12 we=0 hold on port A data=0xcafebabe
[PASS] TC13 we=0 hold on port B data=0xcafebabe
[PASS] TC14 we=0 hold, second cycle data=0xcafebabe
[PASS] TC15 simultaneous read A at 0x010 data=0x11111111
[PASS] TC16 simultaneous read B at 0x011 data=0x22222222
[PASS] TC17 B reads while A writes elsewhere data=0x33333333
[PASS] TC18 A write visible at next read data=0x0dad0000
[PASS] TC19 same addr write/read is read-first data=0x0badf00d
[PASS] TC20 new value visible at next read data=0x12345678
[PASS] TC21 conflict cycle is read-first data=0x0abcdef0
[PASS] TC22 conflict result, port A wins data=0xaaaa5555
[PASS] TC23 conflict result, port B write dropped data=0xaaaa5555
[PASS] TC24 distinct addr write, A effective data=0x77770000
[PASS] TC25 distinct addr write, B effective data=0x88880000
------------------------------------------------------------
[SUMMARY] tb_sram_dp : 25 PASS, 0 FAIL  => ALL PASS
tb_sram_dp.v:186: $finish called at 700000 (1ps)
```

---

## 第三步：Banked SRAM `sram_banked`

命令：

```
iverilog -o sim.out sram_banked.v tb_sram_banked.v && vvp sim.out
```

覆盖：复位清零、写后读回、连续地址跨 bank 同拍并行写
（`0x100/0x101`、`0x102/0x103` 分属不同 bank）、同一 bank 内连续访问
（`0x100/0x104/0x108` 都属 bank 0）、同 bank 双读、bank 冲突 A 优先
（`0x110`/`0x114` 同属 bank 0，B 的写被丢弃）、同 bank 一写一读 read-first、
不同 bank 同拍双写、边界地址 0 / `0x3FF`、`we=0` 保持、读延迟 1 拍。
共 25 项检查。

### 预期终端输出（逐行）

```
[PASS] TC01 sync reset clears rdata_a data=0x00000000
[PASS] TC02 sync reset clears rdata_b data=0x00000000
[PASS] TC03 port A write then read back data=0x00000100
[PASS] TC04 port A reads what port B wrote data=0x00000101
[PASS] TC05 cross-bank 0x100/0x101, port A data=0xaaaa0100
[PASS] TC06 cross-bank 0x100/0x101, port B data=0xbbbb0101
[PASS] TC07 cross-bank 0x102/0x103, port A data=0xcccc0102
[PASS] TC08 cross-bank 0x102/0x103, port B data=0xdddd0103
[PASS] TC09 same-bank addr 0x100 unchanged data=0xaaaa0100
[PASS] TC10 same-bank addr 0x104 decoded data=0x11110004
[PASS] TC11 same-bank dual read, port A data=0x22220008
[PASS] TC12 same-bank dual read, port B data=0x22220008
[PASS] TC13 bank conflict, port A write kept data=0xa1100000
[PASS] TC14 bank conflict, port B write dropped data=0x0bad0bad
[PASS] TC15 same-bank write/read is read-first data=0x0dad0120
[PASS] TC16 new value visible at next read data=0x12340120
[PASS] TC17 different-bank write, port A data=0xaaaa0130
[PASS] TC18 different-bank write, port B data=0xbbbb0131
[PASS] TC19 boundary addr 0 data=0xffffffff
[PASS] TC20 boundary addr MAX data=0x00000001
[PASS] TC21 we=0 hold on port A data=0xcafebabe
[PASS] TC22 we=0 hold on port B data=0xcafebabe
[PASS] TC23 we=0 hold, second cycle data=0xcafebabe
[PASS] TC24 read latency, before posedge data=0xcafebabe
[PASS] TC25 read latency, after posedge data=0xaaaa0100
------------------------------------------------------------
[SUMMARY] tb_sram_banked : 25 PASS, 0 FAIL  => ALL PASS
```

### 真实仿真日志

```
[PASS] TC01 sync reset clears rdata_a data=0x00000000
[PASS] TC02 sync reset clears rdata_b data=0x00000000
[PASS] TC03 port A write then read back data=0x00000100
[PASS] TC04 port A reads what port B wrote data=0x00000101
[PASS] TC05 cross-bank 0x100/0x101, port A data=0xaaaa0100
[PASS] TC06 cross-bank 0x100/0x101, port B data=0xbbbb0101
[PASS] TC07 cross-bank 0x102/0x103, port A data=0xcccc0102
[PASS] TC08 cross-bank 0x102/0x103, port B data=0xdddd0103
[PASS] TC09 same-bank addr 0x100 unchanged data=0xaaaa0100
[PASS] TC10 same-bank addr 0x104 decoded data=0x11110004
[PASS] TC11 same-bank dual read, port A data=0x22220008
[PASS] TC12 same-bank dual read, port B data=0x22220008
[PASS] TC13 bank conflict, port A write kept data=0xa1100000
[PASS] TC14 bank conflict, port B write dropped data=0x0bad0bad
[PASS] TC15 same-bank write/read is read-first data=0x0dad0120
[PASS] TC16 new value visible at next read data=0x12340120
[PASS] TC17 different-bank write, port A data=0xaaaa0130
[PASS] TC18 different-bank write, port B data=0xbbbb0131
[PASS] TC19 boundary addr 0 data=0xffffffff
[PASS] TC20 boundary addr MAX data=0x00000001
[PASS] TC21 we=0 hold on port A data=0xcafebabe
[PASS] TC22 we=0 hold on port B data=0xcafebabe
[PASS] TC23 we=0 hold, second cycle data=0xcafebabe
[PASS] TC24 read latency, before posedge data=0xcafebabe
[PASS] TC25 read latency, after posedge data=0xaaaa0100
------------------------------------------------------------
[SUMMARY] tb_sram_banked : 25 PASS, 0 FAIL  => ALL PASS
tb_sram_banked.v:184: $finish called at 556000 (1ps)
```

---

## 结果汇总

| 模块 | 检查项 | PASS | FAIL |
| --- | --- | --- | --- |
| `sram_sync` | 15 | 15 | 0 |
| `sram_dp` | 25 | 25 | 0 |
| `sram_banked` | 25 | 25 | 0 |
| 合计 | 65 | 65 | 0 |

三组均在 Icarus Verilog 12.0 下真实编译并运行，没有出现 FAIL 用例，
未使用 Python 参考模型替代 RTL 仿真。三个 testbench 各自独立运行，
不依赖其他模块的文件。

## 注意事项

- 阵列不做复位/初始化，未写过的地址读出为不定态 `x`；testbench 中所有
  被检查的读地址都先写过。
- `sram_banked` 的冲突按 **bank 粒度** 判定：即使两个端口写同一 bank 的不同
  bank_addr，B 的写也会被丢弃；这是本实现定义的行为，不是地址粒度仲裁。
- 若某个用例失败，testbench 会打印 `[FAIL] <用例名> got=... exp=...` 并在
  `[SUMMARY]` 中给出 FAIL 数量；本次三组输出中均无 `[FAIL]` 行。
