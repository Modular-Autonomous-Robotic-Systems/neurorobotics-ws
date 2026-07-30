# SBC Design Learning Roadmap v6
## 19-Month Project-Driven Curriculum — 10 Hours/Week
### Target: Jetson Orin Nano Super Carrier Board for Robotics

---

## Preamble

**Total budget**: 84 weeks × 10 hrs/week = **840 hours**. Community consensus (PCBsync, Quora, EEVblog forums): 3–6 months for basic 2-layer boards, 1–2 years for complex multi-layer. At 10 hrs/week part-time, this plan targets functional competence with high-speed 6-layer design in 19 months — aggressive but achievable given your existing embedded systems background. Six weeks added over v5 for: Signal Quality Foundation bridge (2 wks), DFM/thermal in MP5 (1 wk), PDN in MP6 (1 wk), extra layout time in MP10 (1 wk), and bring-up buffer in MP11 (1 wk).

**Assembly**: All SMT components assembled via **JLCPCB Economic Assembly** service. No QFN/LGA/QFP hand-soldering required. Through-hole connectors attached at Stoch Lab soldering station.

**Books**: No library access. PDFs to be sourced and printed. Budget ~₹2,500–3,500 for printing across the plan (~800 pages total at ₹3–4/page).

**Equipment**: All from IISc — Stoch Lab (oscilloscope, bench PSU, soldering station, logic analyzer), DESE (PCB fab, SMT assembly, advanced test equipment), biped hardware experts (mentorship, design review). Personal backup equipment recommended: USB oscilloscope (~₹8,000–15,000) and bench PSU (~₹3,000–5,000) in case lab access is restricted during exam periods.

**No perception work** included. This plan covers hardware/SBC learning + integration with biped only.

---

## Week 0 (Pre-Plan): Establish IISc Lab Access

| Action | Who to Contact | What to Do |
|--------|---------------|------------|
| Stoch Lab equipment audit | Labmates, hardware staff | Confirm oscilloscope model, bench PSU current limit, soldering station type, logic analyzer availability and booking procedure |
| Biped hardware expert mentorship | Hardware support staff | Ask: "Can I bring schematics for 15-min design reviews periodically?" Schedule Week 6 review now. |
| DESE facility access | DESE office / faculty | Can I audit M.Tech EDT lab sessions? Access to SMT assembly line? |
| Software: KiCad 9 | Self | Install KiCad 9 (9.0.x — use v9, not v10, as all tutorial resources target v9). Download from kicad.org |
| Software: LTspice | Self | Install LTspice (Wine on Linux or Windows VM). Download from analog.com/ltspice |
| Software: Saturn PCB Toolkit | Self | Free Windows utility for trace width, via current, diff pair impedance, thermal calculations. Use via Wine/VM. saturnpcb.com/saturn-pcb-toolkit |
| KiCad version control setup | Self | Create GitHub repo. Add `.gitignore` excluding `*-backups/`, `fp-info-cache`, `*.kicad_prl`. Commit at meaningful checkpoints: post-ERC, post-DRC, pre-fab order. |
| Book PDFs | Self | Source PDFs: Erickson & Maksimovic *FPE 3e*, Bogatin *S&PI Simplified*, Horowitz & Hill *AoE 3e*, Johnson & Graham *High-Speed Digital Design*, Ott *EMC Engineering*. Print relevant chapters per milestone. |
| Component lead times | Self | Key parts on LCSC ship 7–14 days. Order components **same day as PCB order** or earlier. |

> **Shipping note**: JLCPCB fabrication is 2–5 days + DHL shipping 5–10 days + customs up to 2 weeks. Budget 2–3 weeks between ordering and receiving. Plan your milestone transitions accordingly.

---

## Phase 1: Foundations — 2-Layer Drone Boards (Weeks 1–24)

---

### MP1: Power Distribution Board (Weeks 1–6)

**Why first**: Power supply design is the #1 cause of board failures. Every subsequent board depends on clean, stable power. Starting here builds a foundation that compounds throughout the plan. **Total: 60 hours.**

| Wk | Resource | Link | Hrs | Description & Focus | Learning Outcome | Project Output |
|----|----------|------|-----|---------------------|-----------------|----------------|
| 1 | NPTEL Basic Electrical Circuits (Krishnapura, IIT Madras), Wks 1–2 | nptel.ac.in/courses/108106172 | 4 | KVL, KCL, nodal analysis, Thevenin/Norton. Watch at 1.25x, pause for handwritten notes. | Analyse voltage dividers under load; understand regulator feedback networks | Notes |
| 1 | NPTEL Fundamental of Power Electronics **NOC version** (Umanand, IISc), Wk 7 | onlinecourses.nptel.ac.in/noc21_ee01/preview | 3 | Buck converter: duty cycle, volt-second balance, inductor/capacitor selection, output ripple. Use **NOC version** — structured weekly content with assignments. Archive course (108108036) has different week numbering. | Understand how a buck converter regulates output voltage | Notes |
| 1 | NPTEL Fundamental of Power Electronics **NOC version** (Umanand, IISc), Wk 6 | onlinecourses.nptel.ac.in/noc21_ee01/preview | 2 | LDO: dropout voltage, thermal limits, output capacitor stability (ESR requirements) | Know how to select and thermally de-rate an LDO for a given load | Notes |
| 1 | Erickson & Maksimovic, *Fundamentals of Power Electronics 3e*, Ch 1–2 (skim) | Print PDF | 3 | Math behind buck converter steady-state. Skim, don't solve every problem — goal is to understand what the NPTEL lectures prove. | Understand derivation behind duty cycle and ripple equations | Notes |
| 2 | TPS563201 Datasheet (Texas Instruments) | ti.com/product/TPS563201 | 3 | Application circuit, inductor selection guide, feedback resistor divider table, layout guidelines section, thermal pad design. **Read the layout guide section twice.** | Can select all external components for TPS563201 from first principles | Notes |
| 2 | AMS1117-3.3 datasheet; IRLML6402 datasheet | lcsc.com or mouser.com | 1 | AMS1117: dropout voltage (1.3V max — note this is high), max input voltage, thermal resistance. IRLML6402: VGS threshold, RDS(on), max current for reverse polarity protection. | Know component specs and can size polarity protection circuit | Notes |
| 2 | TI App Note SLVA139 | ti.com (search SLVA139) | 1 | P-MOSFET reverse polarity protection: operating principle, gate resistor sizing, body diode conduction during insertion transient | Can design a reliable polarity protection circuit | Notes |
| 2 | KiCad 9 Getting Started Guide | docs.kicad.org | 2 | Create project, draw schematic with power symbols, assign footprints from KiCad libraries, run ERC. Set up .gitignore. Commit initial project. | Can create a complete KiCad 9 schematic project with version control | .kicad_pro, .gitignore |
| 3 | Phil's Lab #114 — MLCC Capacitor Basics & Derating | youtube.com/watch?v=kUruN6WBgSw | 1 | MLCC vs electrolytic trade-offs, voltage derating (50% rule), temperature derating, DC bias effect on capacitance (see also #152 for deeper dive) | Select and derate capacitors correctly; understand why a 10µF 6.3V cap at 5V is effectively ~3µF | Notes |
| 3 | Phil's Lab #11 — KiCad STM32 + USB + Buck Converter PCB Design | youtube.com/watch?v=C7-8nUU6e3E | 2 | Watch power section: schematic from datasheet, component selection rationale, layout considerations for buck converter switching node | Understand the full flow from datasheet to schematic to layout | Notes |
| 3 | KiCad 9 | — | 6 | Draw full PDB schematic: XT60 input → IRLML6402 polarity protection → TPS563201 5V buck → AMS1117 3.3V LDO → voltage sense dividers → 4× ESC power pads → status LEDs. Run ERC clean. | Complete, ERC-clean PDB schematic with correct power flags | .kicad_sch |
| 3 | LTspice | analog.com/ltspice | 3 | Simulate TPS563201 buck: transient step load 0→1A, verify output ripple <50mV pk-pk. Verify feedback loop stability (phase margin). This catches feedback resistor errors before layout. | Can verify power supply design using simulation before committing to layout | LTspice .asc |
| 4 | Phil's Lab #65 — KiCad 6 STM32 PCB Full Tutorial (layout sections) | youtube.com/watch?v=aVUqaB0IMh4 | 2 | Watch layout-specific sections: ground plane usage, trace width sizing for power, component placement strategy, thermal via placement under QFN | Understand 2-layer PCB layout principles and apply them to a power board | Notes |
| 4 | Saturn PCB Toolkit | saturnpcb.com/saturn-pcb-toolkit | 1 | Use trace width calculator: size power traces for 5A (verify against IPC-2221). Use via current calculator. Compare with KiCad's built-in calculator. | Can correctly size power traces and vias using industry-standard tools | Notes |
| 4 | KiCad 9 | — | 7 | Layout PDB: follow TPS563201 datasheet layout guide exactly. Place switching node components (inductor, input cap, diode) first. Minimise high-current loop area. Target 45×35mm. Use KiCad impedance calculator for any controlled traces. | Complete, DRC-clean PDB layout following datasheet layout guidelines | .kicad_pcb |
| 5 | JLCPCB ordering guide | jlcpcb.com | 1 | Generate Gerbers from KiCad. Review in JLCPCB Gerber viewer (check copper, silkscreen, drill). Upload and configure order: 2L, HASL, green, quantity 5. Order JLCPCB SMT assembly for TPS563201 (SOT-23-6 or QFN). | Can generate production files and place a JLCPCB order with SMT assembly | Gerbers, BOM, CPL |
| 5 | Robu.in, LCSC, SP Road (Bangalore) | robu.in, lcsc.com | 1 | Order: AMS1117-3.3, IRLML6402, 4.7µH inductor, passives, XT60 connector, JST headers, ESC pads. **Order same day as PCBs to avoid assembly delay.** | Components sourcing pipeline established for future milestones | — |
| 5–6 | NVIDIA P3768 schematic — Power section | developer.nvidia.com/embedded/downloads | 3 | Trace: XT60/barrel input → polarity protection MOSFET → main buck → 5V rail → SoM power pins. For each component write in margin: (1) what it does, (2) why that value. Compare their design choices with yours. | Can read and annotate a production carrier board power tree | Annotated schematic |
| 6 | Stoch Lab bench PSU + oscilloscope | — | 4 | Current-limited power-on at 100mA (no load). Verify 5V and 3.3V rails with DMM. Load test: 5Ω resistor on 5V rail (1A draw). Measure ripple with oscilloscope (10MHz BW). Connect Botlab ESC and flight controller to verify compatibility. | Can systematically test a power supply board from power-on through load test | Test log |
| 6 | Biped hardware expert | — | 2 | Show schematic, LTspice sim, and test results. Ask: "What would you change?" and "What would fail in a noisy flight environment?" | External design review identifies blind spots; understand professional PCB design standards | Review notes |

> **Success criteria**: 5.00V ±100mV under 1A load. Ripple <50mV pk-pk. 3.30V ±66mV from LDO. Board powers Botlab ESC and flight controller without issues.
> **Key risk**: Feedback resistor values giving wrong output voltage — always simulate in LTspice first. If TPS563201 QFN assembly fails at JLCPCB, substitute TPS563200 (SOT-23-6 package, compatible pinout).

---

### MP2: Sensor Breakout Board (Weeks 7–12)

**Why this milestone**: Teaches the most transferable skill for the carrier board — robust sensor interfaces with decoupling, pull-ups, and ESD. The carrier board will have identical circuits at 1.8V logic. **Total: 60 hours.**

| Wk | Resource | Link | Hrs | Description & Focus | Learning Outcome | Project Output |
|----|----------|------|-----|---------------------|-----------------|----------------|
| 7 | NPTEL Basic Electrical Circuits (Krishnapura), Wks 4–5 | nptel.ac.in/courses/108106172 | 3 | Impedance concepts, frequency response, RC circuits. Needed for I2C pull-up sizing and decoupling capacitor placement analysis. | Understand impedance as a function of frequency; can calculate RC rise time | Notes |
| 7 | Bogatin, *Signal & Power Integrity — Simplified*, Ch 1–3 | Print PDF | 4 | Ch 1: Why signals degrade. Ch 2: Ideal and real passive components. Ch 3: Impedance and the power distribution network. Focus: why decoupling matters and how return currents flow through the ground plane. | Understand the physics behind decoupling; know why capacitor placement distance matters | Notes |
| 8 | TI App Note SLVA689 — I2C Pull-up Resistor Calculation | ti.com (search SLVA689) | 2 | Calculate pull-up resistors: bus capacitance from trace + connector + device, target rise time for 400kHz Fast Mode, minimum pull-up for drive strength. Worked examples. | Can correctly size I2C pull-up resistors for a given bus topology | Notes |
| 8 | Nexperia App Note — ESD Protection for I2C/SPI Buses | nexperia.com/applications | 1 | TVS diode selection: clamping voltage, capacitance vs data rate, placement on PCB (ESD device before the bus master). | Can select and place ESD protection correctly on digital buses | Notes |
| 8 | ICM-42688-P, BMP390, LIS3MDL datasheets | invensense.tdk.com, bosch-sensortec.com, st.com | 3 | For each sensor: power supply decoupling requirements (which pins, what capacitor values), SPI/I2C interface timing, recommended layout guidelines. **LIS3MDL**: note magnetic interference — requires ≥15mm keep-out from power inductors, ferrite beads, bulk capacitors (nickel terminations), and high-current traces. | Can read sensor datasheets to extract PCB design requirements | Notes |
| 9 | Phil's Lab #26 — IMU Pmod Board for FPGA | youtube.com/watch?v=UFAj4jJ74oA | 1.5 | IMU sensor PCB design walkthrough: KiCad schematic, decoupling placement, connector design. Note this is FPGA-focused; adapt the sensor interface concepts to your STM32/RPi host. | Understand sensor interface design pattern: power, decoupling, digital interface, ESD | Notes |
| 9 | Phil's Lab #36 — KiCad Breakout Board (STM32 + Sensor) | youtube.com/watch?v=8S8ez1-YwkU | 1.5 | Closer match to this milestone: STM32 + differential pressure sensor breakout. SPI interface, decoupling placement, connector routing. | Understand a complete sensor breakout design with MCU — directly applicable to MP2 | Notes |
| 9 | KiCad 9 | — | 7 | Draw sensor board schematic: ICM-42688-P (SPI) + BMP390 (I2C) + LIS3MDL (I2C), sized pull-ups, TPD4E05U06 ESD on each connector, JST-SH 6-pin connectors for SPI/I2C out. Run ERC clean. | Complete sensor board schematic with proper decoupling, pull-ups, and ESD | .kicad_sch |
| 10 | KiCad 9 | — | 7 | Layout: 2-layer, 30×25mm. Rules: LIS3MDL ≥15mm from power inductors and high-current traces. Decoupling caps <2mm from each sensor VDD pin (use KiCad length tuner to verify). Clean ground plane — no breaks under sensor routing. | Complete, DRC-clean sensor board layout with correct sensor placement constraints | .kicad_pcb |
| 10–11 | NVIDIA P3768 schematic — 40-pin GPIO header + I2C/SPI level shifting section | developer.nvidia.com/embedded/downloads | 3 | Study TXB0108 bidirectional level shifter circuit (3.3V ↔ 1.8V), pull-up strategy for each bus, ESD device placement on external connectors. Annotate — this exact circuit appears on your carrier board. | Understand how to level-shift sensor buses from 3.3V (your boards) to 1.8V (Jetson GPIO) | Annotated schematic |
| 11 | JLCPCB + LCSC | jlcpcb.com, lcsc.com | 1 | Order boards with JLCPCB SMT assembly for all SMT components (QFN/LGA sensors, passives, ESD devices). Separately order remaining through-hole parts. ICM-42688-P ~₹800, BMP390 ~₹400, LIS3MDL ~₹300. | PCB and components ordered; understand SMT assembly BOM/CPL file preparation | Gerbers, BOM, CPL |
| 12 | Stoch Lab bench PSU + STM32 Nucleo or RPi | — | 5 | Power on (current limited). Connect to STM32 Nucleo or RPi via SPI/I2C. Read WHO_AM_I registers from all three sensors to verify assembly. | Validated all sensor interfaces are functional after JLCPCB assembly | Test log |
| 12 | Stoch Lab oscilloscope | — | 3 | Log 10-second IMU data. Calculate noise floor (Allan variance or simple RMS). Compare against Botlab BotStack ICM-42688P spec and your own board's datasheet spec. Measure I2C bus with scope — verify pull-up timing matches calculation. | Can characterise sensor noise floor; can verify I2C timing with oscilloscope | Test log |

> **Success criteria**: All three sensors respond to WHO_AM_I. IMU noise floor within 2× of datasheet spec. I2C bus rise time within 20% of calculated value. No ringing on SPI clock edges.
> **Key learning**: 100nF ceramic within 2mm of every sensor VDD pin is non-negotiable. LIS3MDL placement constraint will recur on the carrier board — internalize it now.

---

### MP3: GPS + Battery Monitor + DSHOT Board (Weeks 13–18)

**Why this milestone**: Introduces mixed-protocol design (UART, I2C, digital), current sensing with Kelvin connections, and timing-sensitive signals (PPS). All appear on the carrier board. **Total: 60 hours.**

| Wk | Resource | Link | Hrs | Description & Focus | Learning Outcome | Project Output |
|----|----------|------|-----|---------------------|-----------------|----------------|
| 13 | Horowitz & Hill, *Art of Electronics 3e*, **Section 14.7** (print PDF) | Print PDF | 3 | Serial buses and data links: UART electrical characteristics, RS-232 vs TTL voltage levels, level shifting topologies. **Note**: this is Section 14.7, not 12.10. | Understand UART voltage level requirements and level shifting for mixed-voltage systems | Notes |
| 13 | NPTEL EMC (KTH/Sweden), **Module 1** | nptel.ac.in/courses/108106138 | 2 | Introduction to EMC: noise sources, coupling mechanisms, common-mode vs differential-mode signals, regulatory context. Course code 108106138, Profs Mansson & Thottappillil. Also available on Ansys Innovation Space (free). | Understand what EMC means, why it matters, and the vocabulary used throughout Phases 2–3 | Notes |
| 14 | INA219 Datasheet (Texas Instruments) | ti.com/product/INA219 | 2 | High-side current sensing architecture, shunt resistor sizing (5mΩ for 20A → 100mV full-scale), Kelvin connection requirement, I2C address configuration, calibration register. **Kelvin connection**: current-sense traces must connect to shunt pads independently from high-current bus — trace resistance adds error. At 20A × 5mΩ, every 0.5mΩ trace = 1% reading error. | Can design and layout a Kelvin-connected current sense circuit | Notes |
| 14 | u-blox NEO-M9N Datasheet + Hardware Integration Manual | u-blox.com | 2 | UART configuration (baud rate, protocol), PPS output (30ns rising-edge accuracy — keep trace <30mm, no vias, away from noisy signals), backup battery circuit, active antenna vs passive antenna, keep-out zone requirement for antenna. | Can correctly integrate a u-blox GPS module including PPS timing constraints | Notes |
| 14 | Betaflight wiki — DSHOT specification | betaflight.com/docs/wiki | 1 | DSHOT 600: bit timing at 600 kbit/s (~1.67µs period), CRC calculation, voltage levels. At this speed on <50mm traces, transmission line effects are negligible. Challenge is noise coupling from motor wires — route DSHOT traces away from motor power on opposite side of ground plane. | Understand DSHOT protocol requirements and why routing discipline (not impedance control) is the key design concern | Notes |
| 14 | Connector selection methodology | Molex, TE, JST datasheets on lcsc.com | 1 | Review JST-GH vs JST-SH vs Molex Picoblade: current rating, mating cycles (500–30 cycles range), keying/polarization, vibration resistance (JST-GH rated for aerospace vibration — correct choice for biped). Apply to this board's connector selection. | Can select connectors based on current rating, mating cycles, and environmental requirements | Notes |
| 15 | KiCad 9 | — | 8 | Schematic: u-blox NEO-M9N (UART + PPS + backup battery) + INA219 (I2C, Kelvin shunt connection) + DSHOT level shifting (SN74LVC1T45, 3.3V→5V) + JST-GH connectors. ERC clean. | Complete GPS/battery/DSHOT schematic | .kicad_sch |
| 16 | KiCad 9 + JLCPCB | jlcpcb.com | 7 | Layout: 2-layer, ~40×35mm. GPS antenna keep-out zone (copper-free area on all layers under ceramic patch antenna). DSHOT traces routed away from GPS module and I2C traces. Shunt resistor with 4-wire Kelvin routing. Fab order with JLCPCB SMT assembly for INA219, SN74LVC1T45, passives. | Complete GPS/monitor/DSHOT layout; boards ordered | .kicad_pcb, Gerbers, BOM |
| 16–17 | NVIDIA P3768 schematic — UART debug header + serial interface section | developer.nvidia.com/embedded/downloads | 3 | Trace UART paths from SoM UART0 to debug header. Study level shifting for 1.8V SoM ↔ 3.3V peripherals. Note PPS signal routing from GPS to SoM on P3768. | Understand how UART and PPS are routed on a production carrier board | Annotated schematic |
| 17–18 | Stoch Lab bench PSU + oscilloscope + Botlab ESC | — | 7 | GPS: achieve satellite lock using u-center. Measure PPS edge with oscilloscope (verify 30ns accuracy is preserved). INA219: calibrate against bench DMM at 3 current levels. DSHOT: send throttle commands and observe motor response with scope measuring DSHOT line. | All three subsystems verified functional; understand timing measurement technique | Test log |

> **Success criteria**: GPS locks within 10 minutes in open sky. PPS edge measurable on oscilloscope. INA219 reads within 2% of DMM. DSHOT controls motor via firmware command.
> **Key insight**: PPS signal preserves 30ns accuracy only if trace is <30mm with no vias and away from noisy signals — this constraint carries directly to the carrier board where PPS synchronises camera and IMU timestamps for VIO/SLAM.

---

### MP4: Integrated Sensor-DSHOT Hub (Weeks 19–24)

**Why this milestone**: First integration challenge — combining multiple functional domains onto one board. Teaches mixed-signal PCB partitioning that directly applies to the carrier board. **Total: 60 hours.**

| Wk | Resource | Link | Hrs | Description & Focus | Learning Outcome | Project Output |
|----|----------|------|-----|---------------------|-----------------|----------------|
| 19 | Ott, *EMC Engineering*, **Ch 10–11 AND Ch 17** (print PDF) | Print PDF | 4 | Ch 10: Digital circuit grounding — ground loop area, return current distribution in ground planes. Ch 11: Digital circuit power distribution — decoupling placement, transient currents. **Ch 17 (critical)**: Mixed-signal PCB layout — when to split planes, mixed-signal IC layout, A/D converter placement, vertical isolation. Ch 10–11 without Ch 17 misses the main lesson for this milestone. | Understand digital grounding principles AND mixed-signal PCB partitioning strategy | Notes |
| 19 | NPTEL EMC (KTH), **Module 2** | nptel.ac.in/courses/108106138 | 2 | Non-ideal behaviour of capacitors, inductors, and resistors at high frequency. PCB trace self-inductance. Why a 100nF cap has a self-resonant frequency above which it looks inductive. | Understand why component placement and package choice affect high-frequency performance | Notes |
| 20 | NPTEL Analog Circuits & Systems 1 (Prof. K Radhakrishna Rao, IIT Madras) | onlinecourses.nptel.ac.in/noc24_ee81/preview | 3 | Lectures on active filters: Butterworth approximation, RC and active filter design for ADC input conditioning. Course code approx. 117108107. Also searchable as "Electronics: Analog Circuits and Systems 1" on YouTube. | Can design a simple anti-aliasing filter for ADC input | Notes |
| 20 | Erickson & Maksimovic, *FPE 3e*, Ch 1–2 review + NPTEL Umanand (NOC) Wk 5 | onlinecourses.nptel.ac.in/noc21_ee01/preview | 2 | Review multi-domain power: multiple regulated domains from single battery input. NPTEL Wk 5: inrush current limiting (NTC thermistor / soft-start circuits). | Can design a power tree for a board with multiple isolated power domains | Notes |
| 21 | KiCad 9 | — | 8 | Hierarchical schematic: consolidate MP2 + MP3 functionality. Sheets: power, sensors (IMU+baro+mag), GPS+PPS, battery monitor, DSHOT, STM32G031 co-processor. Each sheet has clean power symbols and net labels. ERC clean. | Complete hierarchical schematic for the integrated hub board | .kicad_sch |
| 22 | KiCad 9 | — | 8 | Layout: 2-layer, ~60×45mm. **Partition strategy**: DSHOT/motor interface on one end; sensors (IMU, baro, mag) on opposite end; GPS in middle; STM32G031 near sensors. **Do NOT split the ground plane** — use a continuous plane and control where noisy currents flow through placement. LIS3MDL ≥15mm from DSHOT section. Kelvin routing for INA219 shunt. | Complete, DRC-clean integrated hub layout with correct domain partitioning | .kicad_pcb |
| 23 | JLCPCB + Stoch Lab | jlcpcb.com | 3 | Order with JLCPCB SMT assembly for STM32G031, all sensors, INA219, level shifters. Through-hole connectors soldered at Stoch Lab. This board replaces MP2+MP3 on the quadcopter. | Integrated hub assembled and ready for testing | Physical board |
| 24 | Quadcopter + Stoch Lab | — | 5 | Full integration test: all interfaces communicate simultaneously. Compare IMU noise floor on integrated board vs standalone MP2 board (is DSHOT coupling to IMU?). GPS lock time. INA219 current during flight. PPS signal quality with motors running. | Validate that mixed-signal partitioning strategy was effective in real operating conditions | Test log |
| 24 | Seeed OSHW-Jetson-Series repo (GitHub) | github.com/Seeed-Studio/OSHW-Jetson-Series | 3 | Download J401 schematic PDF. Compare: power input range, CAN bus implementation (compare with your INA219/DSHOT design), connector choices. Note Seeed's approach to mixed-signal partitioning on a complex board. | Understand how a production board handles similar integration challenges | Annotated schematic |

> **Success criteria**: All interfaces functional simultaneously during quadcopter flight. IMU noise no worse than standalone MP2 board. Board successfully replaces MP2+MP3 on quad.
> **Ground plane insight**: On 2-layer mixed-signal boards, a continuous ground plane with disciplined component placement outperforms a split ground plane. Return currents take the path of least impedance — at low frequencies this is directly under the signal trace. Place noisy sections (DSHOT) physically away from sensitive sections (sensors); the ground currents stay in their respective regions.

---

## Signal Quality Foundation (Weeks 25–26)

**Purpose**: A 2-week bridge before the first 4-layer board. You cannot design controlled-impedance multi-layer boards without internalising return current paths, grounding, differential signalling, and transmission line theory. These topics are the hardest to learn by accident — they must be studied explicitly. **Total: 20 hours.**

| Wk | Resource | Link | Hrs | Description & Focus | Learning Outcome | Project Output |
|----|----------|------|-----|---------------------|-----------------|----------------|
| 25 | Rick Hartley — "How to Achieve Proper Grounding" (2-hour lecture, Nov 2019) | youtube.com/watch?v=ySuUZEjARPY | 2.5 | **Most important video in the entire plan.** Return current paths, why ground planes work, what happens when signals cross plane splits, loop area minimisation, single-point vs distributed grounding misconceptions. Watch fully, take detailed notes. | Understand why return currents flow directly under signal traces, and what happens when that path is interrupted | Notes |
| 25 | Rick Hartley — "Ground Balance, PCB Design Best Practices, and Common Pitfalls" (Sierra Circuits, Nov 2024) | youtube.com/watch?v=DcninUyq0Pw | 1.5 | Practical grounding guidelines for multi-layer boards: via stitching, split plane handling, connector grounding, plane capacitance. Consolidates the 2019 lecture with more recent examples. | Can apply grounding best practices to a 4-layer or 6-layer PCB layout | Notes |
| 25 | Rick Hartley — "How Grounding Controls Noise and EMI in a PCB" (PCB West 2022) | youtube.com/watch?v=Po_ykTdfEh4 | 1 | How improper grounding creates EMI, how ground plane geometry controls radiated emissions. Connects grounding to the EMC KTH content. | Understand the link between grounding decisions and EMC performance | Notes |
| 25 | Johnson & Graham, *High-Speed Digital Design*, Ch 1 | Print PDF | 1 | High-speed properties of logic gates: rise times, bandwidth, the knee frequency concept. When a signal's bandwidth requires treating a trace as a transmission line. | Know the frequency at which any trace becomes a transmission line | Notes |
| 26 | Johnson & Graham, *High-Speed Digital Design*, **Ch 4** (Transmission Lines) | Print PDF | 2.5 | Transmission line impedance, propagation velocity, reflections from impedance discontinuities, termination strategies, via transitions. **Ch 4 is prerequisite for Ch 5** — do not skip. | Understand what causes signal reflections and how to prevent them through impedance matching | Notes |
| 26 | Johnson & Graham, *High-Speed Digital Design*, Ch 5 | Print PDF | 2 | Ground planes and layer stacking: why ground reference planes work, 4-layer stackup selection, microstrip vs stripline impedance, power plane AC impedance | Can select a 4-layer stackup and calculate trace impedance using manufacturer stackup data | Notes |
| 26 | Phil's Lab #83 — Differential Pairs: PCB Design Basics | youtube.com/watch?v=xwrdvhm4vgw | 1.5 | Differential signalling benefits over single-ended, common-mode rejection, differential impedance definition, intra-pair length matching, inter-pair length matching, routing rules, termination. Essential before MP5 USB routing. | Understand differential pair routing requirements that apply to USB, GbE, CSI, and PCIe in MP5–MP10 | Notes |
| 26 | Bogatin, *Signal & Power Integrity — Simplified*, Ch 4–6 (skim) | Print PDF | 2 | Ch 4: Return currents. Ch 5: Differential pairs. Ch 6: Bandwidth and rise time. Skim to reinforce J&G and Rick Hartley — cross-reference between resources. | Solidify return current and differential pair mental models from multiple sources | Notes |
| 26 | NPTEL Electronic Systems Design: PCB with CAD (Prof. Gupta, IIT Delhi), Wks 9–10 | nptel.ac.in/courses/108102481 | 2 | Course code **108102481**. Wks 9–10: multi-layer PCB concepts, layer assignments, via types (through, blind, buried). Note: course uses CircuitMaker, not KiCad — use for theory only. | Understand multi-layer PCB construction and via types before designing your first 4-layer board | Notes |

> **Checkpoint before MP5**: You should be able to explain (1) why return currents flow under signal traces, (2) what happens if a signal crosses a plane split, (3) what differential impedance means, and (4) when a trace becomes a transmission line. If any of these are unclear, re-watch the relevant Rick Hartley video.

---

## Phase 2: Intermediate — 4-Layer Boards (Weeks 27–50)

---

### MP5: STM32 Flight Computer — First 4-Layer Board (Weeks 27–36)

**Why this milestone**: The jump from 2-layer to 4-layer is the steepest learning curve in PCB design. You're learning stackup definition, controlled impedance, via transitions, and USB differential routing simultaneously. Extra week added for DFM/thermal review after testing. **Total: 100 hours.**

| Wk | Resource | Link | Hrs | Description & Focus | Learning Outcome | Project Output |
|----|----------|------|-----|---------------------|-----------------|----------------|
| 27 | Phil's Lab — Mixed-Signal HW Design with KiCad (paid course, 16 lessons) | phils-lab-shop.fedevel.education (~₹8,500) | 20 | **Highest-ROI resource in the entire plan.** STM32 + USB + buck converter + analog front-end: complete flow from schematic through 4-layer layout in KiCad 9. Watch all 16 lessons with pauses. Practise in KiCad alongside the videos. Budget 20–25 hours total over Weeks 27–28. | Understand the complete mixed-signal PCB design workflow for a 4-layer board in KiCad 9 | Notes + practice KiCad files |
| 28 | Phil's Lab #165 — KiCad 9 Schematic Tutorial (MSPM0-based board, Part 1) | youtube.com/watch?v=O-zNn5k5Bn4 | 1 | KiCad 9-specific schematic features: new symbol library organisation, hierarchical sheets, net inspector, ERC rule customisation. Watch Part 1 (schematic) before Part 2 (PCB). | Familiar with KiCad 9 schematic workflow differences from KiCad 6 | Notes |
| 28 | Phil's Lab #166 — KiCad 9 PCB Layout Tutorial (MSPM0-based board, Part 2) | youtube.com/watch?v=igQWdVGZGpI | 1.5 | KiCad 9-specific PCB features: new stackup editor, impedance calculator, differential pair router, push-and-shove router improvements, 3D viewer | Familiar with KiCad 9 PCB workflow for 4-layer design | Notes |
| 28 | STM32F405RGT6 Datasheet + Reference Manual | st.com | 2 | Multiple VDD power domains (VDD, VDDA, VBAT, VCAP), bypass capacitor requirements for each, VCAP filter for internal LDO, USB OTG FS pin assignment, crystal oscillator load capacitor calculation, SWD debug interface | Can design all STM32F405 support circuitry correctly | Notes |
| 28 | ST App Note AN5407 — STM32F4 PCB Guidelines | st.com (search AN5407) | 1 | ST's own layout recommendations: VCAP placement, bulk vs bypass capacitor ratios, oscillator guard ring, USB signal routing length limits | Know ST's PCB design requirements for STM32F4 peripherals | Notes |
| 28 | JLCPCB impedance calculator + JLC2313 4-layer stackup parameters | jlcpcb.com/pcb-impedance-calculator | 1 | Calculate trace widths for JLCPCB's JLC2313 stackup (1.6mm 4-layer): 50Ω single-ended microstrip on L1/L4, 90Ω differential pair for USB 2.0 on L1. **Always use the manufacturer's stackup data, not generic formulas.** | Can calculate controlled impedance trace widths for JLCPCB's actual stackup | Notes |
| 29 | KiCad 9 | — | 8 | Hierarchical schematic: Power sheet (5V buck → 3.3V LDO → 1.8V LDO, TPS563201 + AMS1117 stages), MCU sheet (STM32F405 + 8MHz crystal + USB-C connector + SWD debug + micro-SD), I/O sheet (all headers matching MP1–MP4 connector pinouts). Clean power symbols and net labels. | Complete STM32 flight computer schematic, ERC-clean, with all support circuitry | .kicad_sch |
| 30 | Biped hardware expert | — | 2 | **Critical pre-layout review.** Bring: printed schematic, JLCPCB stackup data, proposed layer assignment. Ask: decoupling strategy for STM32, USB routing approach, any pinout concerns. Layout changes are 10× more expensive than schematic changes in time — catch problems now. | External review of schematic before committing to layout | Review notes |
| 30–31 | KiCad 9 | — | 12 | 4-layer layout. Stackup: Top Signal – GND – 3.3V – Bottom Signal (JLC2313). Placement: USB-C near MCU, crystal with guard ring, SWD header accessible. Route 90Ω differential USB 2.0 pairs on Top layer over continuous GND on L2. Target 50×50mm. Use KiCad impedance calculator at every trace width decision. | Complete 4-layer STM32 flight computer layout with controlled impedance USB routing | .kicad_pcb |
| 32 | JLCPCB (4-layer with SMT assembly) | jlcpcb.com | 1 | Order 5 boards with JLCPCB assembly for STM32F405 (QFP), all passives, USB-C connector. Specify impedance control (free). Review SMT assembly preview in JLCPCB before confirming. ~₹3,000–5,000 | Boards ordered for assembly | Gerbers, BOM, CPL |
| 32 | ST Nucleo-F405RG schematic (reference) | st.com (search Nucleo-F405RG) | 2 | Study how ST designs their own STM32F405 board — power filtering approach, USB ESD protection, crystal circuit, SWD connector. Compare ST's choices with yours. Note differences and understand why. | Can compare your design against a known-good reference and articulate design trade-offs | Annotated schematic |
| 33 | Stoch Lab (ST-Link + bench PSU) | — | 5 | Flash firmware via SWD. Verify USB enumeration in Linux (`lsusb` — expect FS 12Mbit). Verify each peripheral: SPI/I2C to MP2 sensors, UART to MP3 GPS, DSHOT to Botlab ESC. Fly quadcopter on fully custom avionics stack (PDB + sensor hub + this flight computer). | All interfaces verified functional; custom avionics stack proven in flight | Test log |
| 34 | DFM review + thermal analysis | JLCPCB DFM analysis tool + Saturn PCB Toolkit | 3 | Upload Gerbers to JLCPCB DFM checker — document any violations and how you fixed them. Use Saturn PCB Toolkit: calculate power dissipation of STM32F405 at 168MHz, verify thermal vias under QFP pad are sufficient. TI App Note SLVA462 for general thermal design principles. | Can check a design for manufacturing issues before ordering; can calculate thermal via requirements | Notes |

> **Success criteria**: USB enumerates at FS (12Mbit). All sensor interfaces read correctly. Quad flies. Thermal vias keep STM32 junction temperature within spec.
> **Stackup decision**: JLC2313 stackup — prepreg between L1 and L2 is ~0.21mm, giving 0.127mm trace width for 50Ω microstrip and ~0.18mm/0.20mm spacing for 90Ω differential. Use JLCPCB's calculator with your actual board thickness, not theoretical values.
> **Re-spin budget**: First 4-layer boards frequently need a re-spin. Budget ₹3,000–5,000 for one re-spin. A board that identifies one routing error is a successful learning artifact.

---

### MP6: USB 3.0 Hub + GbE Board (Weeks 37–48)

**Why this milestone**: USB 3.0 at 5 Gbit/s is the hardest routing challenge before the carrier board. Every trace is a transmission line. GbE at 1 Gbit/s has similar constraints. One extra week added for PDN analysis — a critical missing topic. **Total: 120 hours.**

| Wk | Resource | Link | Hrs | Description & Focus | Learning Outcome | Project Output |
|----|----------|------|-----|---------------------|-----------------|----------------|
| 37 | NPTEL EMI/EMC and Signal Integrity (Prof. Bhattacharya, IIT KGP), Wks 1–4 | nptel.ac.in/courses/108105375 | 6 | Course code **108105375**. Wks 1–4: EMI fundamentals, capacitive and inductive coupling mechanisms, signal integrity basics, return current paths at high frequency. Reinforces Rick Hartley content from a more academic perspective. | Understand EMI coupling mechanisms and signal integrity basics needed for USB 3.0 design | Notes |
| 38 | NPTEL EMC (KTH), **Module 3** | nptel.ac.in/courses/108106138 | 2 | Near-end and far-end crosstalk (NEXT/FEXT), spacing rules for parallel traces, guard trace effectiveness (and limitations) | Can calculate required trace spacing to meet crosstalk spec | Notes |
| 38 | Bogatin, *Signal & Power Integrity — Simplified*, Ch 7–9 | Print PDF | 4 | Ch 7: Differential pairs in depth. Ch 8: Via transitions for differential pairs. Ch 9: Return path discontinuities — the most common USB 3.0 routing failure. Focus on what happens to return current at a via transition. | Can design differential pair routing with correct via transitions and continuous return paths | Notes |
| 38 | Bogatin, *S&PI Simplified*, Ch 10–12 (PDN) | Print PDF | 3 | Ch 10: PDN target impedance concept. Ch 11: Decoupling capacitor selection for flat impedance. Ch 12: Power plane resonances and anti-resonance. Essential for USB hub IC power supply design (3.3V, 1.8V, 1.2V rails must meet target impedance). | Understand Power Distribution Network (PDN) design: target impedance, decoupling strategy, plane resonance | Notes |
| 38 | Cadence PDN Design Guide (free) | resources.pcb.cadence.com/blog/2020-your-pdn-design-guide | 1 | Practical guide to PDN design: how to calculate target impedance for a given IC, decoupling capacitor placement rules, power plane pair capacitance | Can apply PDN target impedance methodology to a real board design | Notes |
| 39 | Phil's Lab #143 — Gigabit Ethernet Hardware Design | youtube.com/watch?v=JlAdsK5Z1WI | 2 | RTL8211F PHY: RGMII interface to MAC, magnetics (transformer) selection and placement, MDI termination (100Ω differential), LED configuration, crystal placement with guard ring, decoupling for 1.2V/1.8V/3.3V power domains | Can design a complete GbE PHY circuit | Notes |
| 39 | Phil's Lab #86 — USB Hub Design Walkthrough | youtube.com/watch?v=iR2hYpq0KI0 | 2 | **USB 2.0 High-Speed** hub design walkthrough (this video uses a USB 2.0 IC, not VL817). Study for hub IC methodology: SPI flash for configuration, power distribution to downstream ports, ESD protection placement. For USB 3.0 SuperSpeed specifics, rely on VL817 datasheet and Robert Feranec content. | Understand USB hub IC architecture and configuration approach | Notes |
| 39 | VL817-Q7 Datasheet + VIA Labs Application Notes | lcsc.com (search VL817-Q7) | 3 | USB 3.1 Gen 1 (5 Gbit/s) hub: SPI flash configuration requirements, SuperSpeed TX/RX differential pair routing rules, 90Ω impedance, AC coupling capacitor (100nF) placement, power tree (3.3V, 1.8V, 1.2V generated on-board), ESD requirements on downstream ports | Can design a complete USB 3.1 Gen 1 hub circuit from the datasheet | Notes |
| 40 | Robert Feranec (YouTube) — USB 3.0 PCB Layout videos | youtube.com/@RobertFeranec | 3 | 90Ω differential impedance control, length matching within ±5mil intra-pair and ±100mil inter-pair, AC coupling cap placement (within 200mil of IC), ground via placement at every diff pair via transition, plane continuity under USB SS traces | Can apply USB 3.0 SuperSpeed PCB routing rules | Notes |
| 40 | RTL8211F-CG Datasheet; Pulse J0026D21BNL RJ45+magnetics datasheet | lcsc.com / manufacturer | 2 | RTL8211F: 1.8V CMOS I/O, power-on reset sequence, MDI pin assignment for standard vs crossover. RJ45 with integrated magnetics: coupling ratio, common-mode rejection, pinout for MDI wiring. | Can select and integrate RJ45 connector with magnetics into GbE PHY design | Notes |
| 41 | KiCad 9 | — | 8 | Schematic: USB 3.1 Gen1 hub (VL817-Q7, 4 downstream USB-A ports) + GbE PHY (RTL8211F) + RJ45 with magnetics + power tree (12V→3.3V buck, 3.3V→1.8V LDO, 3.3V→1.2V LDO) + ESD protection on all USB ports. PDN-informed decoupling: calculate target impedance for VL817 VCC and verify decoupling cap selection meets it. ERC clean. | Complete USB hub + GbE schematic with PDN-informed decoupling | .kicad_sch |
| 42–43 | KiCad 9 | — | 14 | 4-layer layout. **Expect this to take longer than planned.** Routing priority: (1) USB 3.0 SS differential pairs (90Ω, ±5mil intra-pair length match, AC coupling caps within 200mil of VL817), (2) GbE MDI pairs (100Ω, keep four pairs equal length), (3) RJ45 magnetics close to PHY, (4) crystal with guard ring, (5) power section, (6) everything else. Verify no plane splits under any differential pair. | Complete 4-layer layout with controlled impedance differential pairs for both USB 3.0 and GbE | .kicad_pcb |
| 44 | Biped hardware expert or DESE contact | — | 2 | **Pre-fab review.** Bring layout files + impedance calculations. Ask: differential pair routing correct? Return path continuity? Any plane splits? AC coupling cap placement? Decoupling approach? | External review of differential pair routing before committing to expensive 4-layer fab | Review notes |
| 44 | JLCPCB (4-layer, impedance control, SMT assembly) | jlcpcb.com/impedance | 1 | Order with impedance control (free at JLCPCB). Specify 90Ω differential on L1 and 100Ω differential on L1 for GbE. JLCPCB provides TDR test coupon on panel to verify. SMT assembly for VL817, RTL8211F, RJ45, all passives. ~₹3,000–4,000. | Boards ordered with impedance control verified by fab | Gerbers, BOM, CPL |
| 45 | P3768 schematic — USB hub (RTS5420) and Ethernet sections | developer.nvidia.com/embedded/downloads | 3 | While waiting for boards: compare your VL817 design vs NVIDIA's RTS5420 implementation. Note: ESD device placement differences, AC coupling cap values, decoupling approach, RJ45 magnetics routing. Annotate all differences. | Understand how a production board implements USB hub and GbE differently from your design | Annotated schematic |
| 46–47 | Stoch Lab + Jetson DevKit | — | 6 | Connect board to Jetson DevKit. `lsusb -t` — verify SuperSpeed (5000M) enumeration on all downstream ports. `ethtool eth0` — verify 1000Mbps link. `iperf3` — measure TCP throughput (target >900 Mbit/s). If USB enumerates at 480M only: impedance mismatch or excessive via stubs — measure with scope. | Verify USB 3.0 SuperSpeed and GbE Gigabit both functional | Test log |
| 48 | Stoch Lab oscilloscope (if USB at 480M or GbE at 100M) | — | 4 | **Debug session (if needed)**: USB at 480M only → probe differential pair with scope, check eye diagram, identify impedance mismatch location. GbE at 100M only → probe MDI pairs, check pair-to-pair crosstalk. Document root cause for re-spin. | Can diagnose and root-cause high-speed signal integrity failures | Test log / re-spin notes |

> **Expect failure**: Many experienced designers report their first USB 3.0 board doesn't achieve SuperSpeed. Common issues: (1) differential pair spacing giving wrong impedance, (2) excessive via stubs, (3) insufficient ground vias at diff pair layer transitions, (4) plane splits under a differential pair. **Budget ₹3,000–4,000 for one re-spin.** A board that identifies one root cause is a successful learning artifact.
> **PDN insight**: The VL817 1.2V supply must maintain <50mΩ target impedance at 100MHz. With JLCPCB's JLC2313 stackup, the L2/L3 power plane pair gives ~200pF/cm² capacitance — calculate whether this alone meets the target or if you need decoupling caps at specific frequencies.

---

### MP7: MIPI CSI-2 Camera Board (Weeks 49–50)

**Why compressed**: By now you've designed 3 boards with controlled impedance differential pairs. CSI-2 routing is similar to USB — 100Ω differential, tight length matching. The new challenge is the FPC connector and camera power management. **Total: 20 hours.**

| Wk | Resource | Link | Hrs | Description & Focus | Learning Outcome | Project Output |
|----|----------|------|-----|---------------------|-----------------|----------------|
| 49 | MIPI Alliance D-PHY specification summary (free overview) | mipi.org | 1 | D-PHY signalling: LP (low-power) mode for control, HS (high-speed) mode for data, differential pair requirements, 100Ω impedance, clock lane requirements. Free overview docs — full spec requires MIPI membership. | Understand MIPI D-PHY physical layer requirements for CSI-2 routing | Notes |
| 49 | NPTEL EMC (KTH), **Module 4: EM Topology & Grounding** | nptel.ac.in/courses/108106138 | 1.5 | **Module 4 covers EM topology and grounding** (not far-field coupling as previously stated). Grounding topologies: single-point, multi-point, hybrid. How ground topology affects return currents at different frequencies. Directly applicable to FPC cable shielding. | Understand grounding topology selection and its frequency-dependent behaviour | Notes |
| 49 | NPTEL EMC (KTH), **Module 5: EM Shielding** | nptel.ac.in/courses/108106138 | 1 | EM shielding effectiveness, aperture effects, shielding for cables and connectors. How FPC cable shielding works (or doesn't). | Can specify cable shielding and connector grounding for a CSI-2 interface | Notes |
| 49 | Phil's Lab #82 — FPGA + PCIe Board Design | youtube.com/watch?v=8bw80LiCl7g | 1.5 | PCIe and CSI-2 share similar routing requirements. Watch for: diff pair length matching technique, via transition design, layer transitions at edge connectors, reference plane continuity at FPC/FFC connectors. | Understand diff pair routing techniques that transfer directly to CSI-2 design | Notes |
| 49 | NVIDIA P3768 schematic — CSI-2 camera connector pages | developer.nvidia.com/embedded/downloads | 2 | Trace CSI-2 lanes from SoM connector → ESD device (TPD4E05U06) → FPC connector. Note: ESD device placement (near FPC, not near SoM), I2C camera control lines, PWDN/RESET, camera power rail (1.8V, 2.8V). This exact circuit appears on your carrier board. | Understand the complete CSI-2 interface circuit for the Jetson carrier board | Annotated schematic |
| 49 | IMX219 Hardware Design Guide; FPC connector datasheet; TPD4E05U06 datasheet | sony-semicon.com, te.com, ti.com | 2 | IMX219: power supply sequencing (1.8V IOVDD before 2.8V AVDD), CSI-2 lane count (2L vs 4L), minimum reset pulse. FPC connector: ZIF vs non-ZIF, contact pitch (0.5mm), current rating. TPD4E05U06: ultra-low capacitance (0.35pF) — critical for preserving 5 Gbit/s CSI-2 signal integrity. | Can select FPC connector and ESD device for CSI-2 application | Notes |
| 50 | KiCad 9 | — | 6 | Schematic + layout: 4-layer. 100Ω differential CSI-2 lanes, length matching within ±0.1mm per lane pair. FPC connector on board edge. ESD devices between FPC and SoM connector pins. Camera power rails with correct power-on sequencing. Fab order with JLCPCB assembly for all SMT parts. | Complete CSI-2 camera board, assembled and tested | .kicad_pcb, Physical board |
| 50 | Jetson DevKit | — | 3 | `v4l2-ctl --list-devices` (verify IMX219 detected). Run GStreamer pipeline: `gst-launch-1.0 nvarguscamerasrc ! nvoverlaysink` (or equivalent). Verify all CSI lanes functional by checking image for missing columns (failed lanes show as vertical stripes). | IMX219 camera functional via CSI-2 interface on Jetson | Test log |

> **Success criteria**: Camera detected by v4l2 subsystem. GStreamer pipeline runs at full resolution. No vertical stripe artifacts (which indicate a failed CSI lane).

---

## Phase 3: Jetson Carrier Board Design (Weeks 51–75)

---

### MP8: Reference Design Deep Dive + Architecture (Weeks 51–58)

**Why 8 weeks**: The most intellectually demanding milestone — no fabrication, pure analysis and design. You're reverse-engineering two production carrier boards and synthesising what you've learned into a complete architecture specification. Extra weeks added for test point planning and the most critical design review. **Total: 80 hours.**

| Wk | Resource | Link | Hrs | Description & Focus | Learning Outcome | Project Output |
|----|----------|------|-----|---------------------|-----------------|----------------|
| 51 | NVIDIA P3768-A04 schematic (all pages printed) | developer.nvidia.com/embedded/downloads | 10 | **The annotation process**: print every page. For each component write in margin: (1) what it does, (2) why that specific part (voltage rating, current, package, cost), (3) what DG-10931-001 says about that section. Focus areas: power tree, SO-DIMM connector routing, USB hub (RTS5420), Ethernet (realtek), CSI-2 connectors, CAN transceivers. | Complete understanding of every design decision in a production Jetson carrier board | Annotated schematic (P3768) |
| 51 | NVIDIA Product Design Guide DG-10931-001 v11 | mouser.com/pdfDocs/Jetson_Orin_NX_... (search "DG-10931-001") | 5 | Read cross-referencing with P3768 schematic: Ch 4 (electrical requirements), Ch 5 (power delivery), Ch 6 (power sequencing), Ch 7 (high-speed interfaces), Ch 8 (low-speed I/O). Mark every requirement that affects your design. | Know all NVIDIA-mandated electrical requirements for a custom carrier board | Annotated DG-10931-001 |
| 52 | Your NVIDIA DevKit (physical board) + DMM | — | 3 | With annotated P3768 schematic in hand: identify every major IC on the physical board. Measure voltages on exposed test points. Trace high-current copper paths visually on the board. Note differences between schematic and physical reality (component markings, silkscreen labels). | Can correlate a schematic with a physical board at the component level | Notes |
| 52 | Seeed OSHW-Jetson-Series repo — J401 + J201 schematics (PDF) | github.com/Seeed-Studio/OSHW-Jetson-Series | 8 | J401 (consumer): note power input range, USB hub IC choice, connector selection. **J201 (industrial, highest value)**: RS-485, digital I/O with optoisolation, CAN bus, PoE. Study Seeed's isolated CAN implementation (compare with your ISO1042 research). Why did Seeed make different choices from NVIDIA's P3768? Annotate. | Understand two alternative production carrier board design philosophies; identify which features to adopt | Annotated J201 schematic |
| 53 | P3768 schematic: power sequencing section (EFM8SB10F2G power MCU) + DG-10931-001 Ch 6 | — | 4 | Power-on/power-off timing sequences, SYS_RESET* signal requirements, carrier board power control responsibilities, CARRIER_PWR_ON signal, voltage monitoring requirements for SoM protection. This is safety-critical — misimplemented sequencing can destroy the ₹15,000 SoM. | Can implement NVIDIA's required power sequencing on a custom carrier board | Notes |
| 53 | NVIDIA Jetson Linux Developer Guide — Custom Carrier Board Adaptation | developer.nvidia.com/embedded/jetson-linux | 3 | Device tree modification process, MB1/MB2 BCT changes, pinmux spreadsheet export to device tree. Understanding what software changes a custom carrier board requires. | Know what BSP (Board Support Package) changes a custom carrier board requires | Notes |
| 54 | NVIDIA Pinmux Spreadsheet for Orin Nano | developer.nvidia.com | 4 | Download the Orin Nano pinmux spreadsheet. For each of your planned interfaces (2× CSI-2, USB 3.2, PCIe M.2, GbE, 4× I2C, 2× SPI, 4× UART, 2× CAN, PPS, PWM, ADC), allocate the required SoM pins. Verify no conflicts. Export device tree snippet for your pin allocation. | Complete pin allocation for your carrier board with no conflicts | Pinmux spreadsheet |
| 54 | ISO1042 Datasheet (TI) + CAN 2.0B physical layer specification | ti.com/product/ISO1042 | 2 | Isolated CAN transceiver: 5kVrms isolation, propagation delay (70ns — verify meets CAN timing budget), isolated power supply options (B0505S-1WR2 isolated 5V/5V DC-DC), termination resistors (120Ω each end of bus), split termination for noise filtering | Can design a complete isolated CAN bus interface for biped actuator control | Notes |
| 55 | Phil's Lab #29 — KiCad RP2040 Module Carrier Board Design | youtube.com/@PhilsLab | 1.5 | Methodology for carrier boards: connector-first approach (place the SoM connector first and route outward), power tree design, I/O allocation, how to handle the large number of SoM pins. | Understand the connector-first methodology for carrier board design | Notes |
| 55 | Phil's Lab #104 — USB-C PD Hardware Design | youtube.com/watch?v=W13HNsoHj7A | 1.5 | USB-C Power Delivery: CC pin configuration, PD negotiation IC selection, VBUS protection, if adding USB-C power input to carrier board. Evaluate whether to include USB-C PD input as alternative to barrel jack. | Can design USB-C power delivery input circuit if desired for carrier board | Notes |
| 56 | Self — Architecture Specification document | — | 8 | Write your carrier board specification. Sections: (1) Requirements (interfaces, power, mechanical), (2) Block diagram, (3) Power tree (9–36V input → protection → buck → rails → sequencing), (4) Layer stackup decision (6-layer), (5) Component selection for new ICs (SO-DIMM connector, power sequencing IC, CAN transceivers), (6) Test point plan (one test point per power rail, one per high-speed interface, SWD access), (7) Pinmux summary. Reuse MP1–MP7 tested sub-circuits wherever possible. | Complete architecture specification for the Jetson Orin Nano Super carrier board | Spec document (PDF/MD) |
| 57 | NPTEL EMC (KTH), **Module 6: Surge Protection & Filters** | nptel.ac.in/courses/108106138 | 1 | Surge protection design, transient filtering for power inputs, common-mode chokes. Relevant for 9–36V battery input protection on carrier board. | Can design input surge protection for a wide-input-range power supply | Notes |
| 57 | NPTEL EMC (KTH), **Module 7: Intentional EMI & Lightning** | nptel.ac.in/courses/108106138 | 0.5 | Intentional radiators, lightning protection — context for understanding why the DG-10931-001 includes certain protection requirements | Context for NVIDIA's EMC requirements | Notes |
| 57 | NPTEL EMC (KTH), **Module 8: EMC Measurements & Standards** | nptel.ac.in/courses/108106138 | 0.5 | EMC test methods (conducted emissions, radiated emissions), relevant standards (CISPR 32, IEC 61000-4-x), what the measurements look for. | Understand what EMC compliance testing measures — relevant for Phase 4 stress testing | Notes |
| 58 | Biped hardware expert + DESE faculty/PhD if available | — | 3 | **Most important review in the entire plan.** Bring: architecture spec, block diagram, power tree, BOM, pinmux spreadsheet, test point plan. Ask: "What architectural errors do you see?" Architectural mistakes caught here save entire board re-spins (~₹10,000 + 2 months each). Specific questions: power sequencing approach, CAN isolation strategy, level shifter placement, mechanical fit with biped chassis. | Architectural errors identified and corrected before any schematic is drawn | Review notes + revised spec |

> **Architecture review is the highest-leverage review in the plan.** A schematic error caught here saves 1–2 weeks. An architectural error caught here saves an entire board re-spin (₹10,000 + 2 months).

---

### MP9: Carrier Board Schematic (Weeks 59–64)

**What you're doing**: Assembling sub-circuits you've already designed and tested (power from MP1, sensor interfaces from MP2/MP4, GPS/DSHOT from MP3, USB from MP6, camera from MP7, CAN from MP8 study) into a single hierarchical schematic. The new elements are the SO-DIMM connector (260-pin), power sequencing per DG-10931-001, and level shifters (all your 3.3V designs must become 1.8V for the Orin's native GPIO). **Total: 60 hours.**

| Wk | Resource | Link | Hrs | Description & Focus | Learning Outcome | Project Output |
|----|----------|------|-----|---------------------|-----------------|----------------|
| 59 | KiCad 9 + DG-10931-001 Ch 5–6 | — | 10 | **Power sheet**: 9–36V input → P-MOSFET polarity protection → TPS54560 or LMR36520 main buck (5V, 10A) → 3.3V LDO → power sequencing logic per DG-10931-001. Include all voltage monitoring, SYS_RESET* generation, carrier power control signals. **SoM connector sheet**: create custom KiCad symbol for 260-pin SO-DIMM connector. Map every pin from your pinmux spreadsheet. Add net labels matching DG-10931-001 signal names. | Power and SoM connector sheets complete with correct sequencing | .kicad_sch (power + SoM sheets) |
| 60 | KiCad 9 + DG-10931-001 Ch 7 | — | 10 | **High-speed interface sheets**: 2× MIPI CSI-2 (ESD + FPC connectors), 1× USB 3.2 Gen1 (ESD + USB-A or Type-C), 1× USB 2.0 debug (Micro-B or Type-A), 1× M.2 Key-M (PCIe x2 + USB 2.0 for NVMe + Wi-Fi), 1× GbE (RTL8211F PHY + RJ45 magnetics). For each interface: verify DG-10931-001 pin assignments, add ESD protection, verify AC coupling cap values. | All high-speed interface schematics complete per DG-10931-001 requirements | .kicad_sch (hi-speed sheet) |
| 61 | KiCad 9 | — | 8 | **Sensor/actuator I/O sheet**: 4× I2C with PCA9306 level shifters (1.8V SoM ↔ 3.3V sensor boards) and ESD, 2× SPI with level shifters, 4× UART (2× direct, 2× optional RS-485 with SP3485 transceiver), 2× isolated CAN (ISO1042 + B0505S-1WR2 isolated power), PPS input (30ns accuracy — short trace, no via), 4× PWM/DSHOT outputs (SN74LVC1T45 level shift 1.8V→5V), 8× analog inputs via ADS131M08 24-bit ADC | All sensor and actuator interfaces complete with correct level shifting and isolation | .kicad_sch (I/O sheet) |
| 62 | KiCad 9 | — | 6 | **Debug and mechanical sheet**: UART console (3.3V USB-UART bridge, e.g. CP2102N), SWD for onboard STM32 co-processor, status LEDs (power good, SoM running, CAN activity), reset button, force recovery button (for JetPack reflash), M3 mounting holes at 4 corners. Add all remaining decoupling capacitors to all sheets. | Complete debug interface and mechanical constraints in schematic | .kicad_sch (debug sheet) |
| 63 | KiCad 9 | — | 5 | **ERC + BOM finalisation**: Run ERC — resolve all errors (not just suppress them — understand each one). Generate BOM from KiCad. Verify every part has: manufacturer part number, LCSC part number (for JLCPCB assembly), second-source alternative for all critical ICs. Check DG-10931-001 for any missed requirements. | Clean ERC. Complete, orderable BOM with all manufacturer part numbers | ERC report, BOM.csv |
| 64 | Biped expert + NVIDIA Developer Forums | forums.developer.nvidia.com | 5 | **Schematic peer review.** Post full schematic to NVIDIA Developer Forums Jetson hardware section for community review. Bring to biped hardware expert. Specific verification points: (1) power sequencing matches DG-10931-001 exactly, (2) all required pull-ups/pull-downs per DG-10931-001 are present, (3) isolation gap for CAN is ≥1.6mm creepage, (4) PPS trace <30mm, (5) level shifter direction logic correct for each bus. | All schematic errors identified and corrected; community review gives independent verification | Review notes + corrected schematic |

> **Success criteria**: Clean ERC. Full BOM with LCSC part numbers. All DG-10931-001 requirements satisfied. Community review on NVIDIA forums received without major issues flagged.

---

### MP10: Carrier Board Layout — 6-Layer (Weeks 65–71)

**The main event.** One extra week over original plan for routing time and PDN verification. **Total: 70 hours.**

| Wk | Resource | Link | Hrs | Description & Focus | Learning Outcome | Project Output |
|----|----------|------|-----|---------------------|-----------------|----------------|
| 65 | JLCPCB impedance calculator + DG-10931-001 layout guidelines + JLC3313 stackup data | jlcpcb.com/pcb-impedance-calculator | 3 | **6-layer stackup (JLC3313)**: Signal–GND–Power–Power–GND–Signal. Two adjacent GND planes give excellent impedance control. Inner power planes carry 5V (L3) and 3.3V (L4). Calculate trace widths: 50Ω SE microstrip on L1/L6, 90Ω diff USB 3.2 on L1, 100Ω diff CSI/GbE on L1, 85Ω diff PCIe on L1. Enter stackup into KiCad board setup. | Can set up a 6-layer stackup in KiCad and calculate correct trace widths using JLCPCB's actual parameters | KiCad board setup |
| 65 | PDN analysis for carrier board | Bogatin Ch 10–12 review + KiCad PDN tools | 2 | Calculate target impedance for Jetson SoM main power rails (VDD_IN, 5V, 3.3V). Verify decoupling strategy from schematic meets target impedance using KiCad's power integrity analysis or manual calculation. Adjust bulk and local decoupling if needed. | Can verify that the carrier board's PDN meets Jetson SoM power delivery requirements | PDN analysis notes |
| 66 | KiCad 9 | — | 8 | **Component placement**: SO-DIMM connector first (fixes one side of the board). Power section: isolated corner away from SoM. High-speed connectors: CSI FPC on edge near camera mounting points, USB-A on edge, M.2 connector position for SSD form factor. Low-speed I/O: header cluster on accessible edge. CAN transceivers: isolated section with ≥1.6mm creepage gap. Power sequencing IC near SoM connector. | All components placed in functional zones before any routing begins | .kicad_pcb (placement) |
| 67 | KiCad 9 | — | 10 | **High-speed routing (routing priority order)**: (1) MIPI CSI-2 lanes (100Ω diff, ±0.1mm intra-pair matching, shortest possible, no layer changes if possible), (2) USB 3.2 SuperSpeed (90Ω diff, length match, AC coupling caps within 200mil of SoM), (3) PCIe x2 to M.2 (85Ω diff, length match within 10mil inter-pair), (4) GbE MDI (100Ω diff, all four pairs equal length). Verify no diff pair crosses a plane split on any layer. | All high-speed differential pairs routed with correct impedance and length matching | .kicad_pcb (hi-speed routed) |
| 68 | KiCad 9 | — | 8 | **Remaining routing**: I2C (keep <50mm traces; pull-ups already in schematic), SPI, UART, CAN (route isolated side traces ≥1.6mm from non-isolated). PWM/DSHOT, PPS (keep <30mm, no vias). GPIO. Power traces: TPS54560 main buck switching node (minimise loop area), distribution traces (width for current + 20% margin). | All signal routing complete | .kicad_pcb (all signals) |
| 69 | KiCad 9 | — | 5 | **Ground and power planes**: Pour GND on L2 and L5 (continuous — check for any unintended islands). Pour 5V on L3, 3.3V on L4. Via stitching on GND: add stitching vias around board perimeter, between high-current return path and main GND, around isolated CAN section boundary. Check thermal relief settings for power vias (use solid connection for power, thermal relief for soldering pads). | Complete poured planes with via stitching | .kicad_pcb (poured) |
| 70 | KiCad 9 | — | 4 | **DRC + 3D review**: Run DRC — resolve all errors. Review in KiCad 3D viewer: check connector clearances, component heights vs chassis constraints, silkscreen legibility. Verify isolation gap for CAN: measure creepage distance in PCB editor (must be ≥1.6mm across all copper layers and surface). | DRC-clean board ready for review | DRC report |
| 70 | Biped expert / DESE | — | 3 | **Layout review**: bring layout files + impedance calculations + plane continuity screenshots. Review focus: high-speed routing correctness, impedance calculations, no plane splits under diff pairs, CAN isolation gap, via stitching adequacy. | External review of 6-layer layout before committing to ₹5,000–8,000 fab order | Review notes |
| 71 | JLCPCB (6-layer, impedance control, SMT assembly) | jlcpcb.com | 2 | Order 5 boards: 6-layer, impedance control (free), specify 90Ω/100Ω/85Ω differential as required. JLCPCB SMT assembly for all SMT components. Include SO-DIMM connector in order (check JLCPCB can source it or supply your own). ~₹5,000–8,000 fab + ₹5,000 assembly + ₹1,500 shipping. Customs: keep each shipment under ₹5,000 declared value if possible. | Carrier board ordered | Gerbers, BOM, CPL |

---

### MP11: Bring-Up (Weeks 72–75)

**The most critical phase.** Inserting a ₹15,000+ SoM into a carrier board with incorrect voltages destroys the SoM. The protocol below is non-negotiable. **Total: 40 hours.**

| Wk | Resource | Link | Hrs | Description & Focus | Learning Outcome | Project Output |
|----|----------|------|-----|---------------------|-----------------|----------------|
| 72 | NVIDIA SDK Manager + custom device tree | developer.nvidia.com | 5 | **While waiting for boards**: Flash custom JetPack image with your device tree and pinmux onto a DevKit first — verify the BSP changes work on known-good hardware before your custom board arrives. Prepare interface test scripts for each peripheral. | BSP ready and verified on DevKit before custom board arrives | Device tree + test scripts |
| 73 | Stoch Lab bench PSU + DMM + oscilloscope | — | 8 | **DO NOT insert SoM. This step is non-negotiable.** (1) No SoM in socket. (2) Current-limited bench supply at 200mA. (3) Measure every power rail with DMM: 5V (must be 4.9–5.1V), 3.3V (3.27–3.33V), 1.8V (1.78–1.82V). (4) Capture power-on sequence with oscilloscope — verify NVIDIA's required sequencing from DG-10931-001 Ch 6. (5) Verify SYS_RESET* timing. (6) Verify all test points accessible. If any rail is wrong: stop, diagnose, fix before proceeding. | All power rails verified correct before SoM insertion | Power-on test log |
| 74 | Stoch Lab | — | 8 | **SoM insertion + boot**: Only after all rails verified. Insert Orin Nano Super SoM. Power on (current-limited, then increase to 2A). Verify UART console output (connect USB-UART bridge to debug UART header). If no output: check USB-UART bridge orientation, verify 3.3V on UART TX pin with scope. Flash JetPack via USB recovery mode if needed. Achieve Linux shell prompt on UART. | JetPack boots on custom carrier board; UART console functional | Boot log |
| 74–75 | Stoch Lab + test equipment | — | 10 | **Systematic interface testing** (test one interface at a time, document pass/fail): USB 3.2 (`lsusb -t`, verify 5000M), GbE (`ethtool`, verify 1000Mbps, run `iperf3`), M.2 (`lspci`, detect NVMe or Wi-Fi), CSI-2 cameras (GStreamer pipeline), I2C buses (`i2cdetect -y N` for each bus), SPI (loopback test), UART (echo test), CAN (`ip link set can0 up type can bitrate 1000000`, candump), PPS (scope on PPS pin), PWM/DSHOT (scope output). | All interfaces tested; pass/fail documented | Interface test log |
| 75 | Self | — | 4 | **Document results**: interface test results table (pass/fail/notes for each interface). Bug list with severity (blocking/non-blocking). Root cause hypothesis for each failure (save root cause analysis for MP12). Rev B plan outline. | Complete test report ready for Rev B planning | Test report, Rev B plan |

> **Pre-insertion power-on protocol** is the most important procedure in this entire plan. The Jetson Orin Nano Super costs ~₹15,000–25,000. If the 5V rail is actually 8V due to a resistor value error, the SoM is permanently destroyed. Measure first, insert later.

---

## Phase 4: Iteration & Hardening (Weeks 76–84)

---

### MP12: Rev B + Stress Testing + Documentation (Weeks 76–84)

**Total: 90 hours.**

| Wk | Resource | Link | Hrs | Description & Focus | Learning Outcome | Project Output |
|----|----------|------|-----|---------------------|-----------------|----------------|
| 76 | Self + mentors | — | 6 | **Root cause analysis**: For each Rev A failure, determine the root cause: power margin error? impedance mismatch? missing pull-up? footprint error? wrong component value? plane split under a critical trace? Write a root cause report — the discipline of understanding *why* prevents recurrence. | Can diagnose PCB failures systematically and identify root causes | Root cause report |
| 77 | KiCad 9 | — | 8 | **Schematic revisions**: Fix all root-cause-confirmed issues. Improve: add test points that were missing in Rev A, improve ESD protection on any interface that showed noise, revise any level shifter that had signal integrity issues. Run ERC clean. | Rev B schematic with all known issues resolved | .kicad_sch (Rev B) |
| 77 | KiCad 9 | — | 6 | **Layout revisions**: Fix routing issues identified in Rev A. Improve via stitching in any area with noise problems. Re-route any impedance-critical trace that was flagged in testing. Run DRC clean. | Rev B layout ready for fabrication | .kicad_pcb (Rev B) |
| 78 | JLCPCB | jlcpcb.com | 1 | Order Rev B: 6-layer, impedance control, SMT assembly. ~₹5,000–8,000. | Rev B ordered | Gerbers (Rev B) |
| 79–80 | Stoch Lab / DESE SMT line | — | 8 | Rev B assembly (JLCPCB SMT) + bring-up using proven procedure from MP11. Verify all Rev A failures are resolved. Systematic interface testing repeat. | Rev B passes all interface tests that Rev A failed | Rev B test log |
| 81 | Stoch Lab + quadcopter/biped | — | 6 | **Motor noise testing**: Run motors at full throttle while Jetson runs compute load. Monitor: Jetson stability (no crashes), sensor data quality (IMU noise floor vs static test), CAN bus error frames (`candump` — count errors), USB link stability. | Board functions correctly in high-noise motor environment | Noise test log |
| 82 | DESE or ETDC Bangalore | stqc.gov.in/etdc-bengaluru-0 | 4 | **ESD testing**: If DESE has an ESD gun, test all external connectors per IEC 61000-4-2 (contact discharge ±4kV, air discharge ±8kV). If not available at DESE, contact ETDC Bangalore (STQC lab) for pre-compliance testing. Document any ESD failures and their pin locations. | Know which interfaces pass ESD robustness testing | ESD test log |
| 82 | Stoch Lab | — | 4 | **Power stress testing**: (1) Reverse polarity at 12V (verify MOSFET protection holds — measure current during test), (2) Overcurrent: short 5V rail through 1Ω resistor (verify e-fuse or current limit trips before damage), (3) Overvoltage: ramp input to 40V (if your protection is rated to 40V), (4) Hot-plug: insert SoM with board powered. | Board withstands all stress test scenarios | Stress test log |
| 83 | Stoch Lab (thermal camera if available via DESE) | — | 4 | **Thermal characterisation**: Run sustained compute load (`stress-ng`) + all interfaces active. Monitor SoM temperature via `tegrastats`. Check carrier board for hot spots with thermal camera or infrared thermometer. Verify thermal pad between SoM and heatsink is correctly installed. | Understand thermal budget and confirm no thermal issues under sustained load | Thermal test report |
| 84 | Self | — | 8 | **Final documentation**: (1) Schematic description (block-by-block explanation of every sub-circuit), (2) Complete BOM with manufacturer PNs and LCSC PNs, (3) Assembly guide (which components are JLCPCB-assembled vs through-hole at Stoch Lab), (4) BSP configuration guide (device tree, pinmux, how to flash JetPack), (5) Test procedures (step-by-step bring-up checklist), (6) Known issues and design rationale notes, (7) Bill of learnings (what you'd do differently on a Rev C). | Complete, transferable documentation package for the carrier board | Documentation package |

---

## Cost Estimates

### PCB Fabrication & Assembly

All SMT assembly via JLCPCB Economic Assembly. Through-hole connectors soldered at Stoch Lab.

| Milestone | Layers | JLCPCB Fab (5 boards) | JLCPCB SMT Assembly | Shipping (DHL) | Subtotal (₹) |
|-----------|--------|----------------------|---------------------|----------------|---------------|
| MP1: PDB | 2 | ₹200 | ₹800 (TPS563201 SOT-23-6 + passives) | ₹500 | 1,500 |
| MP2: Sensor | 2 | ₹200 | ₹1,200 (QFN/LGA sensors + ESD devices) | ₹500 | 1,900 |
| MP3: GPS/DSHOT | 2 | ₹200 | ₹600 (INA219, SN74LVC1T45, passives) | ₹500 | 1,300 |
| MP4: Integrated hub | 2 | ₹300 | ₹1,200 (STM32G031 + all SMT) | ₹500 | 2,000 |
| MP5: STM32 FC | 4 | ₹800 | ₹2,000 (STM32F405 QFP + passives) | ₹800 | 3,600 |
| MP5: Re-spin (budget) | 4 | ₹800 | ₹2,000 | ₹800 | 3,600 |
| MP6: USB+GbE | 4 | ₹800 | ₹2,500 (VL817, RTL8211F, RJ45, passives) | ₹800 | 4,100 |
| MP6: Re-spin (likely) | 4 | ₹800 | ₹2,500 | ₹800 | 4,100 |
| MP7: Camera | 4 | ₹800 | ₹600 (ESD devices, passives) | ₹800 | 2,200 |
| MP9–10: Carrier board | 6 | ₹5,000 | ₹6,000 (all SMT — many ICs) | ₹1,500 | 12,500 |
| MP12: Carrier Rev B | 6 | ₹5,000 | ₹6,000 | ₹1,500 | 12,500 |
| **Fabrication total** | | | | | **~₹49,300** |

*JLCPCB prices are estimates. Actual prices depend on board dimensions, SMT component count, and current exchange rates. Customs under ₹5,000 per shipment typically cleared without duty — consider splitting large shipments. Order boards and components simultaneously to avoid delays.*

### Components (Not Included in JLCPCB Assembly)

| Category | Estimated Cost (₹) | Notes |
|----------|-------------------|-------|
| Power components (TPS563201, AMS1117, MOSFETs, passives) | 1,000 | MP1 — most passives covered by JLCPCB assembly |
| Sensors (ICM-42688-P, BMP390, LIS3MDL) | 2,500 | MP2 + spares |
| GPS module (u-blox NEO-M9N) | 2,000 | MP3 |
| INA219, level shifters, CAN transceivers | 1,500 | MP3–MP4 |
| STM32F405 + crystal (if not in JLCPCB SMT) | 800 | MP5 backup |
| USB hub IC (VL817-Q7), GbE PHY (RTL8211F), RJ45 w/magnetics | 2,500 | MP6 |
| IMX219 camera module + FPC cable | 1,500 | MP7 |
| Jetson carrier board components (SO-DIMM connector, ISO1042, SP3485, PCA9306, ADS131M08, all connectors) | 14,000 | MP9–MP10 — SO-DIMM connector alone ~₹3,000–5,000 |
| Carrier Rev B components (partial reorder) | 5,000 | MP12 |
| Miscellaneous (flux, JST connectors, headers, ribbon cables, thermal pads) | 3,000 | Ongoing |
| **Components total** | **~₹33,800** | |

### Courses & Books

| Item | Cost (₹) | Notes |
|------|----------|-------|
| Phil's Lab — Mixed-Signal HW Design with KiCad | 8,500 | Fedevel Education, ~$99 USD. phils-lab-shop.fedevel.education |
| Book PDFs printing (6 books, selected chapters, ~800 pages) | 2,500 | ₹3–4/page at photocopy shop |
| NPTEL courses | 0 | Free to audit. NPTEL certification optional (~₹1,100/exam) |
| **Courses & books total** | **~₹11,000** | |

### Total Cost Summary

| Category | ₹ |
|---------|---|
| PCB fabrication & assembly | 49,300 |
| Components | 33,800 |
| Courses & books | 11,000 |
| **Prototyping total** | **~₹94,100** |
| Personal backup equipment (USB scope + bench PSU, optional) | 11,000–25,000 |
| Certification (production only, per model) | 85,000–2,50,000 |
| **Grand total (through production readiness)** | **₹1,90,000–3,70,000** |

### Certification & Compliance Testing (Future — Not Required During Learning)

| Item | Cost (₹) | Timeline | Lab |
|------|----------|----------|-----|
| EMC pre-compliance testing | 25,000–50,000 | 1–2 weeks | ETDC Bangalore (STQC, stqc.gov.in/etdc-bengaluru-0) |
| BIS CRS lab testing | 50,000–1,50,000 | 4–8 weeks | BIS-recognised lab (ETDC, UL India, EMTAC/Vimta Bangalore) |
| BIS CRS application + registration | 10,000–30,000 | 4–12 weeks after test | Online via BIS portal |
| BIS label review & documentation | 5,000–15,000 | — | — |
| BIS consultant (optional) | 20,000–50,000 | — | HardFault, Om Garuda Group |
| EMC full compliance (CE/FCC if exporting) | 50,000–2,00,000 | 2–4 weeks | UL Solutions Bangalore, Tata Advanced Systems (Electronics City) |

*BIS CRS certification is compulsory for notified electronic products sold in India. A carrier board sold as a component to B2B customers may not require CRS — verify with a compliance consultant.*

---

## Mentorship Touchpoints

| When | Who | What to Bring | Expected Outcome |
|------|-----|--------------|-----------------|
| Week 6 (MP1 done) | Biped hardware expert | PDB schematic + LTspice sim + test log | Feedback on power design approach, test methodology, what to improve |
| Week 30 (MP5 pre-layout) | Biped hardware expert | STM32 schematic + proposed 4-layer stackup + JLCPCB impedance calc | Catch schematic and stackup errors before layout. Advice on USB routing, decoupling strategy. Layout changes are 10× more expensive than schematic changes. |
| Week 44 (MP6 pre-fab) | Biped expert or DESE contact | USB 3.0/GbE layout files + impedance calculations | Review differential pair routing and impedance calculations. Identify any plane splits or via transition issues. |
| Week 57 (MP8 architecture) | Biped expert + DESE faculty/PhD if possible | Architecture spec, block diagram, power tree, BOM, pinmux, test point plan | **Most important review.** Architectural errors caught here save entire board re-spins (~₹10,000 + 2 months) |
| Week 63 (MP9 schematic done) | All available reviewers + NVIDIA Developer Forums | Complete carrier board schematic + ERC report + BOM | Final schematic review before committing to 6-layer layout. Verify power sequencing compliance with DG-10931-001. |
| Week 70 (MP10 pre-fab) | Biped expert / DESE | 6-layer layout files + impedance calculations + plane continuity screenshots | Review high-speed routing, plane continuity, CAN isolation gap (≥1.6mm), via stitching |

---

## Timeline Visualization

```
Month 1:   [Wk 1–4]   MP1: Power Distribution Board .................. 2L
Month 2:   [Wk 5–6]   MP1: Fab + Test + Review
           [Wk 7–8]   MP2: Sensor Board — Theory ..................... 2L
Month 3:   [Wk 9–12]  MP2: Design → Fab → Test
Month 4:   [Wk 13–16] MP3: GPS + Battery + DSHOT — Theory + Design ... 2L
Month 5:   [Wk 17–18] MP3: Fab + Test
           [Wk 19–20] MP4: Integrated Hub — Theory ................... 2L
Month 6:   [Wk 21–24] MP4: Design → Fab → Test
Month 7:   [Wk 25–26] SIGNAL QUALITY FOUNDATION ...................... ★ Bridge
           [Wk 27–28] MP5: STM32 FC — Phil's Lab paid course ......... 4L ★
Month 8:   [Wk 29–32] MP5: Schematic → Review → Layout → Fab
Month 9:   [Wk 33–34] MP5: Test + DFM/Thermal review
           [Wk 37–38] MP6: USB+GbE — SI + PDN Theory ................. 4L ★★
Month 10:  [Wk 39–43] MP6: IC datasheets → Schematic → Layout
Month 11:  [Wk 44–47] MP6: Review → Fab → Test
Month 12:  [Wk 48]    MP6: Debug (expect re-spin)
           [Wk 49–50] MP7: Camera Board ................................ 4L
           [Wk 51–52] MP8: P3768 + DG-10931-001 Deep Dive
Month 13:  [Wk 53–55] MP8: Seeed J401/J201 + Sequencing + BSP + Pinmux
Month 14:  [Wk 56–58] MP8: Architecture Spec + CAN + Review (most important!)
           [Wk 59–60] MP9: Carrier Schematic — Power + SoM + Hi-Speed . 6L ★★★
Month 15:  [Wk 61–63] MP9: I/O + Debug + ERC + BOM
           [Wk 64]    MP9: Schematic peer review
           [Wk 65]    MP10: Stackup + PDN analysis
Month 16:  [Wk 66–69] MP10: Placement → Hi-Speed → Remaining → Planes
Month 17:  [Wk 70–71] MP10: DRC → Review → Fab order
           [Wk 72–73] MP11: BSP prep + Power-on test (NO SoM!)
Month 18:  [Wk 74–75] MP11: SoM insertion + Boot + Interface test
           [Wk 76–77] MP12: Root cause + Rev B schematic + layout
Month 19:  [Wk 78–84] MP12: Rev B fab + test + stress + thermal + docs

★ Bridge = Signal quality foundation before 4-layer work
★ = complexity jump (first 4-layer)
★★ = high-speed challenge (USB 3.0 SuperSpeed)
★★★ = the main event (Jetson carrier board)
```

---

## What Success Looks Like

**Month 6**: Quadcopter flying on your custom integrated sensor/DSHOT hub. You can read any power supply or sensor interface datasheet confidently. You understand why component placement matters.

**Month 9**: First 4-layer board designed and flying as a flight computer. You understand stackup selection, impedance control, and the Phil's Lab paid course has given you a repeatable design workflow.

**Month 12**: USB 3.0 SuperSpeed verified working (or you've done a re-spin and understand exactly why it failed). GbE at 1 Gbps. You can discuss differential pair routing with any professional PCB designer.

**Month 14**: You have fully annotated schematics for two production Jetson carrier boards (NVIDIA P3768 and Seeed J201). You understand every design decision. Your architecture spec has been reviewed and approved.

**Month 19**: A custom Jetson Orin Nano Super carrier board you designed from scratch boots JetPack, with all sensor and actuator interfaces tailored for your robotics biped platform. Rev B is stress-tested, thermally characterised, and fully documented. The same board will run your biped's perception and planning software.
