# SBC Design Learning Roadmap v5
## 18-Month Project-Driven Curriculum — 10 Hours/Week
### Target: Jetson Orin Nano Super Carrier Board for Robotics

---

## Preamble

**Total budget**: 78 weeks × 10 hrs/week = **780 hours**. Community consensus (PCBsync, Quora, EEVblog forums): 3–6 months for basic 2-layer boards, 1–2 years for complex multi-layer. At 10 hrs/week part-time, this plan targets functional competence with high-speed 6-layer design in 18 months — aggressive but achievable given your existing embedded systems background.

**Books**: No library access. PDFs to be sourced and printed. Budget ~₹2,000–3,000 for printing across the plan.

**Equipment**: All from IISc — Stoch Lab (oscilloscope, bench PSU, soldering), DESE (PCB fab, SMT assembly, advanced test equipment), biped hardware experts (mentorship, design review).

**No perception work** included. This plan covers only hardware/SBC learning + integration with biped.

---

## Week 0 (Pre-Plan): Establish IISc Lab Access

| Action | Who to Contact | What to Ask |
|--------|---------------|-------------|
| Stoch Lab equipment audit | Labmates, hardware staff | What oscilloscope, bench PSU, soldering station, logic analyzer is available? When can I use it? |
| Biped hardware expert mentorship | Hardware support staff | "Can I bring my board schematics to you for 15-min reviews periodically?" |
| DESE facility access | DESE office / faculty | Can I use PCB fab lab for 2-layer prototypes? Can I audit M.Tech EDT lab sessions? |
| DESE SMT assembly | DESE ESP lab | Can I use the SMT line for my carrier board prototype (Month 15)? |
| Software setup | Self | Install KiCad 9, LTspice (Wine on Linux). Create GitHub repo for hardware projects. |
| Book PDFs | Self | Source PDFs for Erickson & Maksimovic, Bogatin, Horowitz & Hill, Johnson & Graham, Ott. Print relevant chapters per milestone. |

---

## Week-by-Week Plan

### Phase 1: Foundations — 2-Layer Drone Boards (Weeks 1–24)

| Milestone | Week | Learning Items | Learning Resource | Focus | Reference/Link |
|-----------|------|---------------|-------------------|-------|----------------|
| **MP1: Power Distribution Board** | 1 | Circuit fundamentals: KVL, KCL, nodal analysis, Thevenin/Norton | NPTEL — Basic Electrical Circuits (Krishnapura, IIT Madras), Weeks 1–2 | Analyse voltage dividers under load; understand regulator feedback networks | nptel.ac.in/courses/108106172 (YouTube playlist also available) |
| | 1 | DC-DC buck converter operation, steady-state analysis | NPTEL — Fundamental of Power Electronics (Umanand, IISc), Week 7 lectures only | Buck converter: duty cycle, inductor/capacitor selection, output ripple | nptel.ac.in/courses/108108036 (archive) ; NOC version at onlinecourses.nptel.ac.in |
| | 1 | LDO regulator operation and design | NPTEL — Fundamental of Power Electronics (Umanand, IISc), Week 6 lectures only | Dropout voltage, thermal limits, output capacitor stability | Same as above |
| | 2 | Datasheet reading: buck converter | TPS563201 Datasheet (Texas Instruments) | Application circuit, inductor selection guide, feedback resistor divider, layout guidelines, thermal pad | ti.com/product/TPS563201 |
| | 2 | Datasheet reading: LDO, P-MOSFET | AMS1117-3.3 datasheet; IRLML6402 datasheet | Dropout, max input voltage; VGS threshold, RDS(on) for reverse polarity protection | Search on LCSC.com or Mouser |
| | 2 | Reverse polarity protection circuit | TI App Note SLVA139 | P-MOSFET reverse polarity protection topology, component selection | ti.com (search SLVA139) |
| | 2 | KiCad basics | KiCad 9 official Getting Started guide | Create project, draw schematic, assign footprints, ERC | docs.kicad.org |
| | 3 | MLCC capacitor selection and derating | Phil's Lab #114 (YouTube) | MLCC vs electrolytic, voltage derating, temperature derating, placement | youtube.com/@PhilsLab |
| | 3 | Buck converter PCB design workflow | Phil's Lab #11 (YouTube), power section only | Schematic from datasheet, component selection, layout considerations | youtube.com/@PhilsLab |
| | 3 | Schematic design practice | KiCad 9 | Draw full PDB schematic: XT60 → MOSFET protection → TPS563201 buck → AMS1117 LDO → voltage sense → ESC pads → LEDs | — |
| | 3 | Circuit simulation | LTspice | Simulate TPS563201 buck: transient step load 0→1A, verify output ripple <50mV | analog.com/en/resources/design-tools-and-calculators/ltspice-simulator.html |
| | 4 | 2-layer PCB layout fundamentals | Phil's Lab #65 (YouTube), layout sections | Ground plane, trace widths for power, component placement, thermal vias | youtube.com/@PhilsLab |
| | 4 | PCB layout practice | KiCad 9 | Layout PDB: follow TPS563201 datasheet layout guide exactly; 45×35mm board | — |
| | 5 | Gerber generation and fab ordering | JLCPCB ordering guide | Generate Gerbers, review in viewer, order 5 boards (~₹500 + ₹500 shipping) | jlcpcb.com |
| | 5 | Component sourcing | Robu.in, LCSC, SP Road (Bangalore) | Order TPS563201, AMS1117, IRLML6402, passives, connectors | robu.in, lcsc.com |
| | 5–6 | Reference design study (continuous) | NVIDIA P3768 schematic — Power section | Trace input protection → buck → sequencing → SoM power pins. Annotate. | developer.nvidia.com (search "Jetson Orin Nano carrier board") |
| | 6 | Soldering and assembly | Stoch Lab soldering station | Hand-solder through-hole; hot air for QFN (or use JLCPCB assembly for TPS563201) | — |
| | 6 | Power-on testing | Stoch Lab bench PSU + oscilloscope | Current-limited power-on at 100mA; measure 5V/3.3V rails; load test with 5Ω resistor; measure ripple | — |
| | 6 | **Design review** | Biped hardware expert | Show schematic + test results. Ask: "What would you change?" | — |
| **MP2: Sensor Breakout Board** | 7 | Impedance concepts, frequency response | NPTEL — Basic Electrical Circuits (Krishnapura), Weeks 4–5 | Understanding impedance for I2C pull-up sizing and decoupling analysis | nptel.ac.in/courses/108106172 |
| | 7 | Decoupling theory and practice | Book: Bogatin, *Signal & Power Integrity — Simplified*, Ch 1–3 (print PDF) | Why decoupling matters; capacitor placement; return currents through ground plane | Print from PDF |
| | 8 | I2C electrical design | TI App Note SLVA689: "I2C Pull-up Resistor Calculation" | Calculate pull-ups: bus capacitance, speed mode, rise time | ti.com (search SLVA689) |
| | 8 | ESD protection for digital buses | Nexperia App Note: "ESD protection for I2C/SPI" | TVS diode selection, parasitic capacitance vs data rate trade-off | nexperia.com/applications |
| | 8 | Sensor datasheets | ICM-42688-P, BMP390, LIS3MDL datasheets | Power decoupling requirements, SPI/I2C timing, magnetic interference (LIS3MDL placement) | invensense.tdk.com, bosch-sensortec.com, st.com |
| | 9 | Sensor board schematic and layout | Phil's Lab #26 (YouTube): IMU Pmod board | Sensor PCB design walkthrough: KiCad schematic, decoupling placement, layout | youtube.com/@PhilsLab |
| | 9 | Schematic design | KiCad 9 | ICM-42688-P (SPI) + BMP390 + LIS3MDL (I2C), pull-ups, ESD (TPD4E05U06), JST-SH connectors | — |
| | 10 | Layout practice | KiCad 9 | 2-layer, 30×25mm. LIS3MDL ≥15mm from power traces. Decoupling caps <2mm from sensor VDD | — |
| | 10–11 | Reference design study (continuous) | NVIDIA P3768 — 40-pin header, I2C/SPI level shifting | Study TXB0108 level shifter circuit, pull-up strategy, ESD placement | — |
| | 11 | Fab order + component sourcing | JLCPCB + LCSC | Order boards and sensors (ICM-42688-P ~₹800, BMP390 ~₹400, LIS3MDL ~₹300) | jlcpcb.com, lcsc.com |
| | 12 | Assembly and testing | Stoch Lab | Hot-air reflow for QFN/LGA sensors. Read WHO_AM_I registers via STM32 Nucleo or RPi | — |
| | 12 | Noise characterisation | Stoch Lab oscilloscope | Log IMU data; compare noise floor against Botlab BotStack onboard ICM-42688P | — |
| **MP3: GPS + Battery Monitor + DSHOT Board** | 13 | UART interface electrical design | Book: Horowitz & Hill, *Art of Electronics* 3e, Section 12.10 (print PDF) | UART voltage levels, RS-232 vs TTL, level shifting circuits | Print from PDF |
| | 13 | EMC fundamentals | NPTEL — EMC (KTH/Sweden), Module 1 | EMC principles, noise sources, common-mode vs differential-mode signals | nptel.ac.in/courses/108106138 ; also on Ansys Innovation Space (free) |
| | 14 | Current sensing design | INA219 datasheet (Texas Instruments) | High-side sensing, shunt sizing (5mΩ for 20A max → 100mV full-scale), Kelvin connection | ti.com/product/INA219 |
| | 14 | GPS module integration | u-blox NEO-M9N datasheet + hardware integration manual | UART config, PPS output (30ns edge accuracy), backup battery, antenna keep-out zone | u-blox.com |
| | 14 | DSHOT protocol | Betaflight wiki — DSHOT specification | Bit timing at 600 kbit/s, CRC, signal integrity requirements for clean edges near motor wires | betaflight.com/docs/wiki |
| | 15 | Schematic design | KiCad 9 | u-blox NEO-M9N (UART+PPS) + INA219 (I2C) + DSHOT level shifting (SN74LVC1T45) + JST-GH connectors | — |
| | 16 | Layout + fab order | KiCad 9, JLCPCB | 2-layer, ~40×35mm. GPS antenna keep-out zone. DSHOT traces routed away from GPS and I2C lines | jlcpcb.com |
| | 16–17 | Reference design study (continuous) | NVIDIA P3768 — UART debug header, serial interfaces | Trace UART paths, level shifting for 1.8V SoM ↔ 3.3V peripherals | — |
| | 17–18 | Assembly and testing | Stoch Lab | GPS lock (u-center). PPS timing (oscilloscope). INA219 calibration vs bench DMM. DSHOT motor control with Botlab ESC | — |
| **MP4: Integrated Sensor-DSHOT Hub** | 19 | Mixed-signal PCB partitioning | Book: Ott, *EMC Engineering*, Ch 10–11 (print PDF) | Ground plane design: analog/digital separation, single-point vs distributed grounding | Print from PDF |
| | 19 | EMC: high-frequency component behaviour | NPTEL — EMC (KTH), Module 2 | Non-ideal behaviour of caps, inductors, resistors at high frequency; PCB trace as transmission line | nptel.ac.in/courses/108106138 |
| | 20 | Anti-aliasing filter design | NPTEL — Analog Circuits & Systems 1 (IIT Madras/TI), Lectures on active filters | Butterworth approximation, RC/active filter for ADC input conditioning | nptel.ac.in (search "Analog Circuits Systems") |
| | 20 | Multi-domain power design | Book: Erickson & Maksimovic, Ch 1–2 review + NPTEL Umanand Week 5 (inrush limiting) | Multiple regulated domains from single input; inrush current handling | Print from PDF; nptel.ac.in/courses/108108036 |
| | 21 | Schematic: consolidation | KiCad 9 | Single board integrating MP2+MP3 functionality: IMU+baro+mag+GPS+PPS+INA219+DSHOT routing + STM32G031 co-processor | — |
| | 22 | Layout: first complex 2-layer | KiCad 9 | 2-layer, ~60×45mm. Partition: GPS section, sensor section (keep mag away from power), DSHOT section. Careful ground plane design | — |
| | 23 | Fab + assembly | JLCPCB + Stoch Lab | This board replaces MP2+MP3 on quad | jlcpcb.com |
| | 24 | Integration test | Quadcopter | Full flight test with integrated board. Compare sensor noise to standalone boards. Verify all interfaces | — |
| | 24 | Reference design study (continuous) | Seeed J401 schematic (from GitHub) | Compare J401 power input range, CAN implementation, connector choices vs P3768 | github.com/Seeed-Studio/OSHW-Jetson-Series |

### Phase 2: Intermediate — 4-Layer Boards (Weeks 25–46)

| Milestone | Week | Learning Items | Learning Resource | Focus | Reference/Link |
|-----------|------|---------------|-------------------|-------|----------------|
| **MP5: STM32 Flight Computer (first 4-layer)** | 25 | Complete mixed-signal design workflow | Phil's Lab — Mixed-Signal HW Design with KiCad (paid course, 5h 20min video) | STM32 + USB + buck + analog front-end: schematic through 4-layer layout in KiCad. **Highest-ROI resource in entire plan.** | phils-lab.net/courses (~₹8,500) |
| | 26 | 4-layer PCB theory | NPTEL — Electronic Systems Design: PCB with CAD (Prof. Gupta, IIT Delhi), Weeks 9–10 | Multi-layer PCB concepts, through-hole vs blind/buried vias, layer assignment | nptel.ac.in (search "Electronic Systems Design PCB") |
| | 26 | Stackup and ground planes | Book: Johnson & Graham, *High-Speed Digital Design*, Ch 1 and Ch 5 (print PDF) | When a trace becomes a transmission line; 4-layer stackup Signal-GND-Power-Signal | Print from PDF |
| | 27 | STM32 hardware design | STM32F405 datasheet + reference manual; ST App Note AN5407 (PCB guidelines) | Multiple VDD domains, bypass/VCAP requirements, USB OTG FS, crystal oscillator layout | st.com |
| | 27 | KiCad 9 workflow | Phil's Lab #166 (YouTube): KiCad 9 tutorial | Latest KiCad version: stackup editor, impedance calculator, differential pair router | youtube.com/@PhilsLab |
| | 28 | Schematic design | KiCad 9 | Hierarchical schematic: power (5V buck → 3.3V LDO → 1.8V LDO), STM32F405 + crystal + USB-C + SWD + micro-SD, all sensor/actuator headers matching MP1–MP4 connectors | — |
| | 29 | **Design review (critical)** | Biped hardware expert | Review schematic + proposed stackup **before layout**. Ask about decoupling strategy and USB routing | — |
| | 29–30 | 4-layer PCB layout | KiCad 9 | Stackup: Top Sig – GND – 3.3V – Bot Sig. 90Ω diff for USB 2.0. Target 50×50mm. Use JLCPCB impedance calculator. | jlcpcb.com/pcb-impedance-calculator |
| | 31 | Fab order (JLCPCB assembly for STM32 QFP) | JLCPCB | Use JLCPCB SMT assembly service for STM32 + fine-pitch passives. Hand-solder connectors at lab. ~₹3,000–5,000 | jlcpcb.com |
| | 31 | Reference design study | ST Nucleo-F405RG schematic | Study how ST designs their own STM32 evaluation boards — power, USB, crystal, debug | st.com (search Nucleo-F405RG schematic) |
| | 32 | Assembly + bring-up | Stoch Lab | Flash via SWD (ST-Link). Verify USB enumeration (`lsusb`). Test each interface with MP1–MP4 boards | — |
| | 33 | Flight test | Quadcopter | Fly quad on fully custom avionics stack: your PDB + sensor hub + flight computer | — |
| **MP6: USB 3.0 Hub + GbE Board** | 34 | Signal integrity fundamentals | NPTEL — EMI/EMC and Signal Integrity (Prof. Bhattacharya, IIT KGP), Weeks 1–4 | EMI fundamentals, coupling mechanisms, signal integrity basics, return current paths | nptel.ac.in (search "EMI EMC Signal Integrity") |
| | 35 | EMC: crosstalk and near-field coupling | NPTEL — EMC (KTH), Module 3 | Near-end and far-end crosstalk, spacing rules for parallel traces, guard traces | nptel.ac.in/courses/108106138 |
| | 35 | Differential pair routing theory | Book: Bogatin, *Signal & Power Integrity*, Ch 7–9 (print PDF) | Differential impedance, length matching, via transitions for diff pairs, return path continuity | Print from PDF |
| | 36 | GbE hardware design | Phil's Lab #143 (YouTube) | RTL8211F PHY: RGMII interface, magnetics selection, MDI termination, LED config, layout | youtube.com/@PhilsLab |
| | 36 | USB 3.0 hub design | Phil's Lab #86 (YouTube) | VL817 hub IC: SPI flash config, USB 3.x SuperSpeed routing, ESD protection, power | youtube.com/@PhilsLab |
| | 37 | USB 3.0 PCB layout practices | Robert Feranec (YouTube): USB 3.0 layout videos | 90Ω differential impedance, length matching within ±5mil, AC coupling cap placement | youtube.com/@RobertFeranec |
| | 37 | Datasheets | VL817-Q7, RTL8211F-CG, RJ45 with magnetics (e.g., Pulse J0026D21BNL) | Hub IC pin assignments, PHY power domains (1.2V/1.8V/3.3V), magnetics specs, connector pinout | Via LCSC or manufacturer sites |
| | 38 | Schematic design | KiCad 9 | USB 3.0 hub (4 downstream ports) + GbE PHY + RJ45 + power tree (3.3V, 1.8V, 1.2V) + ESD | — |
| | 39–40 | 4-layer layout (expect this to be hard) | KiCad 9 | 90Ω diff USB SS pairs, 100Ω diff GbE MDI. Length matching. Crystal close to PHY with guard ring. **Budget extra time.** | — |
| | 40 | **Design review** | Biped hardware expert or DESE contact | Review differential pair routing and impedance calculations before ordering | — |
| | 41 | Fab order | JLCPCB with impedance control | Impedance control is **free** at JLCPCB as of 2026. Specify 90Ω diff and 100Ω diff requirements. ~₹2,000–3,000 | jlcpcb.com/impedance |
| | 42 | Reference design study | P3768 — USB hub (RTS5420) and Ethernet sections | Compare your VL817 design vs NVIDIA's RTS5420 implementation. Note ESD, routing, decoupling differences | — |
| | 43–44 | Assembly + testing | Stoch Lab + Jetson DevKit | Connect to Jetson DevKit. `lsusb -t` (verify 5000M SuperSpeed). `ethtool` (verify 1000Mbps). `iperf3` for throughput. | — |
| | 44 | Debug if needed | Stoch Lab oscilloscope | If USB at 480M only → impedance mismatch. If GbE at 100M only → MDI routing or magnetics issue. Measure signal with scope. | — |
| **MP7: MIPI CSI Camera Board** | 45 | MIPI CSI-2 physical layer | MIPI Alliance D-PHY specification summary (free overview) | D-PHY signaling: LP/HS modes, differential pairs, 100Ω impedance requirement | mipi.org (free overview docs) |
| | 45 | EMC: shielding and far-field coupling | NPTEL — EMC (KTH), Modules 4–5 | Electromagnetic shielding effectiveness, solutions to EMC problems in cables and connectors | nptel.ac.in/courses/108106138 |
| | 45 | Differential pair routing for CSI | Phil's Lab #82 (YouTube): FPGA + PCIe design | PCIe and CSI share similar routing: diff pair routing techniques, length matching, via transitions | youtube.com/@PhilsLab |
| | 45 | Reference design: camera section | NVIDIA P3768 — CSI-2 camera connector pages | Trace CSI lanes from SoM to FPC connector. Note ESD (TPD4E05U06), decoupling, I2C for camera control | — |
| | 46 | Datasheets | IMX219 hardware design guide, FPC connector datasheet, TPD4E05U06 | Camera power requirements, CSI lane assignment, FPC connector selection, ESD capacitance budget | sony-semicon.com, te.com, ti.com |
| | 46 | Schematic + layout | KiCad 9 | 4-layer. 100Ω diff CSI lanes, length matching within ±0.1mm per lane pair. FPC on board edge. | — |
| | 46 | Testing | Jetson DevKit | `v4l2-ctl --list-devices`, GStreamer capture. Verify all CSI lanes functional. | — |

### Phase 3: Jetson Carrier Board Design (Weeks 47–68)

| Milestone | Week | Learning Items | Learning Resource | Focus | Reference/Link |
|-----------|------|---------------|-------------------|-------|----------------|
| **MP8: Reference Design Deep Dive + Architecture** | 47 | Exhaustive P3768 annotation | NVIDIA P3768 schematic (print all pages) + Product Design Guide DG-10931-001 | Every IC, every component value, every design choice. Cross-reference with DG-10931-001 requirements. | developer.nvidia.com |
| | 47 | Physical board inspection | Your NVIDIA DevKit (physical board) + multimeter | With schematic in hand, identify every IC. Measure voltages on test points. Trace high-current copper paths visually. | — |
| | 48 | Seeed J401 + Industrial J201 study | Seeed OSHW-Jetson-Series repo (Cadence Allegro + PDF) | J401: consumer design. J201: RS-485, DI/DO, CAN, PoE — closer to your robotics needs. Why did Seeed make different choices? | github.com/Seeed-Studio/OSHW-Jetson-Series |
| | 48 | Power sequencing deep dive | P3768 schematic: power MCU (EFM8SB10F2G) + DG-10931-001 Ch 6 | SYS_RESET*, power-on/off timing, carrier board power control, NVIDIA's sequencing requirements | — |
| | 49 | Carrier board BSP preparation | NVIDIA Jetson Linux Developer Guide — Custom Carrier Board Adaptation | Device tree modification, MB1/MB2 BCT changes, pinmux spreadsheet for custom carrier board | developer.nvidia.com/embedded/jetson-linux |
| | 49 | Carrier board pinmux | NVIDIA Pinmux Spreadsheet for Orin Nano | Allocate every pin for your carrier board's interfaces. Export device tree configuration. | developer.nvidia.com |
| | 50 | CAN bus design for biped actuators | ISO1042 datasheet (TI); CAN 2.0B specification (physical layer) | Isolated CAN transceiver: isolation voltage, propagation delay, isolated power supply (B0505S-1WR2) | ti.com/product/ISO1042 |
| | 50 | Carrier board architecture specification | Self-authored document | Requirements document, block diagram, BOM (reuse tested circuits from MP1–MP7), power tree, 6-layer stackup, pinmux | — |
| | 51 | Phil's Lab carrier board reference | Phil's Lab #29 (YouTube): KiCad RP2040 Module Carrier Board Design | Methodology for designing a carrier board around a SoM: connector-first approach, power tree, I/O allocation | youtube.com/@PhilsLab |
| | 51 | USB-C power delivery | Phil's Lab #104 (YouTube): USB-C PD Hardware Design | If adding USB-C power input to carrier board: PD negotiation IC, CC pin configuration | youtube.com/@PhilsLab |
| | 52 | **Architecture review (most important review)** | Biped hardware expert + DESE faculty/PhD if possible | Review full architecture spec, block diagram, power tree, BOM. Catch architectural errors before schematic. | — |
| **MP9: Carrier Board Schematic** | 53 | Schematic: power sheet | KiCad 9 | 9–36V input → P-MOSFET protection → TPS54560/LMR36520 buck → 5V → AMS1117 3.3V LDO → power sequencing per DG-10931-001 | — |
| | 53 | Schematic: SoM connector | KiCad 9 | 260-pin SO-DIMM connector. Map every pin from pinmux spreadsheet. Create custom KiCad symbol. | — |
| | 54 | Schematic: high-speed interfaces | KiCad 9 | 2× MIPI CSI-2, 1× USB 3.2, 1× USB 2.0 debug, 1× M.2 Key M (PCIe x2), 1× GbE with PHY + magnetics | — |
| | 55 | Schematic: sensor/actuator I/O | KiCad 9 | 4× I2C (PCA9306 level shifters, ESD), 2× SPI, 4× UART (optional RS-485), 2× isolated CAN (ISO1042), PPS, 4× PWM/DSHOT, analog inputs (ADS131M08 ADC) | — |
| | 56 | Schematic: debug + mechanical | KiCad 9 | UART console, SWD for onboard MCU, status LEDs, reset/recovery buttons, M3 mounting holes | — |
| | 57 | ERC + BOM finalisation | KiCad 9 | Clean ERC. Complete BOM with manufacturer part numbers. Verify all parts available on LCSC/Mouser. Second-source critical components. | — |
| | 58 | **Schematic peer review** | Biped expert + NVIDIA Developer Forums | Post schematic for review. Verify power sequencing compliance with DG-10931-001. Check for missing pull-ups/pull-downs. | forums.developer.nvidia.com |
| **MP10: Carrier Board Layout (6-layer)** | 59 | 6-layer stackup design | JLCPCB impedance calculator + DG-10931-001 layout guidelines | Stackup: Sig–GND–Pwr–Pwr–GND–Sig. Calculate trace widths: 50Ω SE, 90Ω diff (USB), 100Ω diff (CSI, PCIe), 85Ω diff (PCIe alt). JLCPCB provides JLC3313 stackup for 6-layer. | jlcpcb.com/pcb-impedance-calculator |
| | 59 | EMC: system topology | NPTEL — EMC (KTH), Modules 6–8 | System-level EMC design, surge protection, filtering, EMC measurements and standards | nptel.ac.in/courses/108106138 |
| | 60 | Component placement | KiCad 9 | SO-DIMM connector first → power section (isolated corner) → high-speed connectors → low-speed I/O → mechanical | — |
| | 61 | High-speed routing | KiCad 9 | USB 3.2 (90Ω), PCIe (85Ω), CSI (100Ω), GbE (100Ω). Length match within pairs. No signal over plane splits. | — |
| | 62 | Remaining routing + planes | KiCad 9 | I2C, SPI, UART, CAN, GPIO. Pour ground and power planes. Via stitching. | — |
| | 63 | DRC + Gerber review | KiCad 9 | Clean DRC. Review in 3D viewer. Check isolation gaps for CAN (≥1.6mm creepage). | — |
| | 64 | **Layout review** | Biped expert / DESE | Review high-speed routing, impedance calculations, plane continuity, isolation gaps | — |
| | 64 | Fab order | JLCPCB | 6-layer with impedance control. ~₹5,000–8,000 for 5 boards + ₹2,000 shipping. | jlcpcb.com |
| **MP11: Bring-Up** | 65 | BSP finalisation | NVIDIA SDK Manager + custom device tree | Flash custom JetPack image with your device tree and pinmux. Prepare test scripts for each interface. | developer.nvidia.com |
| | 66 | Power-on sequence (most critical step) | Stoch Lab bench PSU + oscilloscope | **DO NOT insert SoM.** Current-limited PSU at 200mA. Verify all rails: 5V (±2%), 3.3V (±2%). Check sequencing with scope. | — |
| | 67 | SoM insertion + boot | Stoch Lab | Insert SoM only after all rails verified. Flash JetPack. Boot. Verify console on UART debug. | — |
| | 67–68 | Systematic interface testing | Stoch Lab + test equipment | USB enumeration, GbE link, camera capture (GStreamer), I2C sensor reads, CAN bus communication, UART, PPS | — |
| | 68 | Document results | Self | Interface test results. Bug list. Rev B plan. | — |

### Phase 4: Iteration & Hardening (Weeks 69–78)

| Milestone | Week | Learning Items | Learning Resource | Focus | Reference/Link |
|-----------|------|---------------|-------------------|-------|----------------|
| **MP12: Rev B + Documentation** | 69 | Root cause analysis | Self + mentors | For each bug: understand *why* it failed (power margin? impedance mismatch? missing pull-up? footprint error?) | — |
| | 70 | Schematic + layout revisions | KiCad 9 | Fix all issues from MP11. Improve layout based on testing experience. | — |
| | 71 | Rev B fab order | JLCPCB | Order revised boards. ~₹5,000–8,000 | jlcpcb.com |
| | 72 | Rev B assembly + test | Stoch Lab / DESE SMT line | If DESE SMT access available, use it for professional assembly. Otherwise JLCPCB assembly. | — |
| | 73 | Motor noise testing | Stoch Lab + quadcopter/biped | Run motors at full throttle. Monitor Jetson stability. Check sensor data quality. | — |
| | 74 | ESD testing | DESE or ETDC Bangalore | If DESE has ESD gun: test external connectors per IEC 61000-4-2. If not, contact ETDC Bangalore (STQC lab) for pre-compliance. | stqc.gov.in/etdc-bengaluru-0 |
| | 75 | Power stress testing | Stoch Lab | Reverse polarity test (verify MOSFET protects). Overcurrent test (verify e-fuse trips). Overvoltage test. | — |
| | 76 | Thermal characterisation | Stoch Lab (thermal camera if available) | Run sustained compute load. Monitor SoM and carrier board temps. Verify thermal pad and heatsink mounting. | — |
| | 77–78 | Documentation | Self | Complete docs: schematic description, BOM, assembly guide, BSP config guide, test procedures, known issues, design rationale | — |

---

## Deep Dive by Milestone

### MP1: Power Distribution Board (Weeks 1–6)

**Why this first**: Power supply design is the #1 cause of board failures and the area where your existing knowledge is weakest. Every subsequent board depends on clean, stable power. Starting here builds a foundation that compounds throughout the plan.

**Time budget**: 60 hours (10 hrs/week × 6 weeks)

| Activity | Hours | Notes |
|----------|-------|-------|
| NPTEL lectures (Krishnapura Wk1–2, Umanand Wk6–7) | 10 | Watch at 1.25x speed. Pause to take handwritten notes. |
| Datasheet reading + app notes | 6 | TPS563201 is the most important. Read the layout guide twice. |
| Phil's Lab videos + KiCad setup | 4 | #11 and #114 plus KiCad Getting Started |
| Book chapters (Erickson Ch1–2, skim) | 3 | Math behind buck converter steady-state. Skim, don't solve problems. |
| Schematic design in KiCad | 10 | Including LTspice simulation of buck. Your first real schematic. |
| PCB layout | 8 | Follow TPS563201 layout guide exactly. This is where you learn PCB-specific skills. |
| Gerber gen + ordering + component sourcing | 2 | Straightforward once schematic/layout are done |
| Assembly | 4 | First time soldering — expect to be slow. Hot-air for QFN if doing it yourself. |
| Testing + debug | 8 | Power-on, voltage measurement, load test, oscilloscope ripple check. |
| Reference design study (P3768 power) | 3 | Annotate the P3768 power tree while your own design is fresh. |
| Design review with mentor | 2 | 15–30 min conversation, but prep your questions beforehand |

**Key risks**: QFN soldering (TPS563201 is 2×2mm). Mitigation: use the SOT-23-6 variant TPS563200 if hot-air is unavailable, or use JLCPCB assembly (add ~₹500–800). Another risk: incorrect feedback resistor values giving wrong output voltage. Mitigation: always simulate in LTspice first.

**What success looks like**: 5.00V ±100mV output under 1A load. Ripple <50mV pk-pk. 3.30V ±66mV from LDO. No magic smoke. Board powers your Botlab ESC and flight controller.

---

### MP2: Sensor Breakout Board (Weeks 7–12)

**Time budget**: 60 hours

This milestone teaches you the *most transferable skill for the carrier board*: designing robust sensor interfaces with proper decoupling, pull-ups, and ESD protection. The Jetson carrier board will have identical circuits — just more of them and at 1.8V logic levels.

**Key learning**: The difference between a sensor that works on a breadboard and one that works reliably in a noisy robot environment comes down to: decoupling (100nF ceramic within 2mm of every power pin), proper I2C pull-up sizing (too strong = overshoot/ringing; too weak = slow edges/missed acks), and ESD protection on every connector that touches the outside world.

**Critical detail — magnetometer placement**: The LIS3MDL is sensitive to DC magnetic fields from current-carrying traces and ferromagnetic components. Place it ≥15mm from: power inductors, ferrite beads, bulk capacitors with nickel terminations, and high-current motor wires. Orient it away from the PDB's buck converter. This constraint will recur on the carrier board.

---

### MP3: GPS + Battery Monitor + DSHOT Board (Weeks 13–18)

**Time budget**: 60 hours

**DSHOT signal integrity rationale**: DSHOT 600 operates at 600 kbit/s with ~1.67µs bit period. At this speed, on a short PCB trace (<50mm), transmission line effects are negligible. However, the signal quality challenge is *noise coupling* — the DSHOT traces run near high-current motor wires (on the ESC). The solution isn't impedance control (not needed at 600 kbit/s on short traces) but *routing discipline*: keep DSHOT traces away from motor power traces, route them on the opposite side of the ground plane if possible, and use a clean reference plane beneath them.

**PPS timing**: The NEO-M9N PPS output has 30ns rising-edge accuracy. To preserve this on your PCB: keep the PPS trace short (<30mm), route it away from noisy digital signals, and avoid vias in the PPS path. On the Jetson carrier board, this PPS signal will synchronise your camera and IMU timestamps — critical for VIO/SLAM.

**INA219 current sensing**: Use Kelvin connection to the shunt resistor (4-wire sensing). This means the current-sense traces connect to the resistor pads independently from the high-current bus traces. Without Kelvin connection, trace resistance adds error. At 20A and 5mΩ, the full-scale voltage is only 100mV — every 0.5mΩ of trace resistance is a 1% error.

---

### MP4: Integrated Sensor-DSHOT Hub (Weeks 19–24)

**Time budget**: 60 hours

This is your first *integration* challenge — combining multiple functional domains onto one board. The learning goal is **mixed-signal partitioning**: how to physically organise a PCB so that noise from one domain (DSHOT/motor interface) doesn't contaminate another (IMU, barometer, magnetometer).

**Ground plane strategy**: On a 2-layer board with mixed signals, you *cannot* split the ground plane (a common misconception). Instead, use a continuous ground plane and control *where the noisy currents flow* through component placement: place the DSHOT/motor interface section on one end of the board, sensors on the other, GPS in between (it's relatively noise-immune), and the STM32G031 co-processor near the sensors it reads. Return currents follow the path of least impedance, which at low frequencies is under the signal trace — so noisy traces routed over one section of ground don't contaminate the ground under sensors on the other section.

---

### MP5: STM32 Flight Computer — First 4-Layer Board (Weeks 25–33)

**Time budget**: 90 hours (9 weeks — the most time-intensive milestone, justified by the complexity jump)

**Why 9 weeks**: Community consensus is that the jump from 2-layer to 4-layer is the steepest learning curve in PCB design. You're learning: stackup definition, plane assignment, controlled impedance calculation, via transitions between layers, power plane design, and USB differential pair routing — all at once. The Phil's Lab paid course (5h 20min video, but ~20–25 hours with pausing and practice) is essential preparation.

**4-layer stackup decision**: Signal–GND–3.3V–Signal. With JLCPCB's standard 1.6mm 4-layer JLC2313 stackup, the prepreg between Layer 1 (top signal) and Layer 2 (GND) is ~0.21mm. This gives ~0.127mm trace width for 50Ω microstrip. For 90Ω differential USB 2.0, use the KiCad impedance calculator with JLCPCB's stackup parameters. **Always use the manufacturer's stackup data, not generic formulas.**

**Design review timing**: Get the schematic and proposed stackup reviewed by the biped hardware expert *before* starting layout. Layout changes are 10× more expensive than schematic changes in time.

---

### MP6: USB 3.0 Hub + GbE Board (Weeks 34–44)

**Time budget**: 110 hours (11 weeks — the hardest routing challenge before the carrier board)

**Why this is hard**: USB 3.0 SuperSpeed operates at 5 Gbit/s. At this speed, every trace is a transmission line. Impedance mismatches cause reflections that corrupt data. The PHY and hub IC compensate for moderate impairments, but poor routing means the link negotiates down to USB 2.0 High-Speed (480 Mbit/s) — a 10× throughput loss. Similarly, GbE uses 4 differential pairs at 125 MHz with PAM-5 encoding; impedance mismatch or crosstalk between pairs degrades the link to 100 Mbps.

**JLCPCB impedance control**: As of 2026, JLCPCB provides impedance control as a **free service**. You specify target impedance per layer in the order form, they adjust manufacturing parameters, and include a TDR test coupon on your panel. This removes the biggest risk from high-speed design — you don't need to guess whether your traces are actually 90Ω.

**Expect failure**: Many experienced designers report that their first USB 3.0 board doesn't achieve SuperSpeed on the first spin. Common issues: incorrect differential pair spacing (impedance too high/low), excessive via stubs (use back-drill or blind vias if the fab supports it), insufficient ground vias near diff pair via transitions, or plane splits under the diff pair. **Budget ₹2,000–3,000 for a re-spin.** A board that only works at USB 2.0 speeds is still a valuable learning artifact — it tells you exactly what to fix.

---

### MP7: MIPI CSI Camera Board (Weeks 45–46)

**Time budget**: 20 hours (compressed — you've already done high-speed diff pair routing in MP6)

By this point, you've designed 3 boards with controlled impedance differential pairs (USB in MP5, USB 3.0 + GbE in MP6). CSI-2 routing is similar: 100Ω differential, tight length matching. The new challenge is the FPC connector (small, fragile, polarised) and camera power management.

---

### MP8: Reference Design Deep Dive + Architecture (Weeks 47–52)

**Time budget**: 60 hours

**This is the most intellectually demanding milestone.** No fabrication. Pure analysis and design.

**What you're doing**: Reverse-engineering two production carrier boards (NVIDIA P3768 and Seeed J401/J201) at the component level, then synthesising what you've learned into an architecture specification for your own board.

**The annotation process**: Print every schematic page. For each component, write in the margin: (1) what it does, (2) why that specific part was chosen (voltage rating, current rating, package, cost), (3) what the Design Guide DG-10931-001 says about that section. This takes 20–30 hours for two designs but gives you an irreplaceable understanding of production carrier board engineering.

**Seeed Industrial J201 is particularly valuable** because it includes RS-485, DI/DO (digital input/output with optoisolation), CAN, and PoE — industrial I/O that's closer to your robotics requirements than the consumer-oriented P3768. Study how Seeed implements galvanic isolation for CAN (likely ISO1042 or similar) and compare with your MP4 design.

---

### MP9: Carrier Board Schematic (Weeks 53–58)

**Time budget**: 60 hours

You're assembling sub-circuits you've already designed and tested (power from MP1, sensor interfaces from MP2/MP4, DSHOT/PWM from MP3, USB from MP6, camera from MP7, CAN from MP8 study) into a single hierarchical schematic. The new elements are: the SO-DIMM connector (260-pin, requiring a custom KiCad symbol), power sequencing (following NVIDIA's specific requirements), and adapting all your 3.3V designs to the Orin's 1.8V native GPIO (requiring level shifters like PCA9306 on every I/O bus).

---

### MP10: Carrier Board Layout — 6-Layer (Weeks 59–64)

**Time budget**: 60 hours

**6-layer stackup (JLCPCB JLC3313)**: Signal–GND–Power–Power–GND–Signal. This gives two reference planes (Layer 2 GND and Layer 5 GND) adjacent to the two signal layers, providing excellent impedance control and return current paths. The inner power planes (Layers 3 and 4) carry 5V and 3.3V.

**Routing priority order**: (1) MIPI CSI-2 lanes — shortest, most sensitive. (2) USB 3.2 SuperSpeed — 90Ω diff, length matched. (3) PCIe x2 to M.2 — 85Ω diff. (4) GbE MDI — 100Ω diff. (5) Power traces — wide, short, heavy copper. (6) Everything else (I2C, SPI, UART, CAN, GPIO).

---

### MP11: Bring-Up (Weeks 65–68) and MP12: Rev B (Weeks 69–78)

**Time budget**: 40 + 100 hours

**The pre-insertion power-on test cannot be skipped.** Inserting a ₹15,000+ SoM into a carrier board with incorrect voltages will destroy the SoM. The protocol: (1) No SoM in socket. (2) Apply power via current-limited bench supply at 200mA. (3) Measure every rail with DMM. (4) Capture power-on sequence with oscilloscope. (5) Only insert SoM after all rails verify.

---

## Cost Estimates

### PCB Fabrication & Assembly

| Milestone | Layers | JLCPCB Fab (5 boards) | JLCPCB Assembly | Shipping (DHL) | Subtotal (₹) |
|-----------|--------|----------------------|-----------------|----------------|---------------|
| MP1: PDB | 2 | ₹200 | — (hand-solder) | ₹500 | 700 |
| MP2: Sensor | 2 | ₹200 | ₹500 (QFN sensors) | ₹500 | 1,200 |
| MP3: GPS/DSHOT | 2 | ₹200 | — | ₹500 | 700 |
| MP4: Integrated hub | 2 | ₹300 | ₹800 (STM32G031) | ₹500 | 1,600 |
| MP5: STM32 FC | 4 | ₹800 | ₹1,500 (STM32F405) | ₹800 | 3,100 |
| MP6: USB+GbE | 4 | ₹800 | ₹2,000 (USB hub, PHY) | ₹800 | 3,600 |
| MP6: Re-spin (likely) | 4 | ₹800 | ₹2,000 | ₹800 | 3,600 |
| MP7: Camera | 4 | ₹800 | ₹500 | ₹800 | 2,100 |
| MP9–10: Carrier board | 6 | ₹4,000 | ₹5,000 | ₹1,500 | 10,500 |
| MP12: Carrier Rev B | 6 | ₹4,000 | ₹5,000 | ₹1,500 | 10,500 |
| **Fabrication total** | | | | | **~₹37,600** |

*Note: JLCPCB prices are estimates based on typical board sizes. Actual prices depend on dimensions, component count, and current exchange rates. Customs under ₹5,000 per shipment typically cleared without duty.*

### Components

| Category | Estimated Cost (₹) | Notes |
|----------|-------------------|-------|
| Power components (TPS563201, AMS1117, MOSFETs, passives) | 1,500 | MP1 + spares |
| Sensors (ICM-42688-P, BMP390, LIS3MDL) | 2,500 | MP2 + spares |
| GPS module (u-blox NEO-M9N) | 2,000 | MP3 |
| INA219, level shifters, CAN transceivers | 1,500 | MP3–MP4 |
| STM32F405 + crystal + USB-C + passives | 1,500 | MP5 (if not using JLCPCB assembly) |
| USB hub IC (VL817), GbE PHY (RTL8211F), RJ45+magnetics | 2,500 | MP6 |
| Camera module (IMX219/RPi Camera v2) + FPC connector | 1,500 | MP7 |
| Jetson carrier board components (SO-DIMM connector, all ICs, connectors, passives) | 12,000 | MP9–MP10 |
| Carrier Rev B components | 5,000 | MP12 — partial reorder |
| Miscellaneous (solder paste, flux, JST connectors, headers, wires) | 3,000 | Ongoing |
| **Components total** | **~₹33,000** | |

### Courses & Books

| Item | Cost (₹) | Notes |
|------|----------|-------|
| Phil's Lab — Mixed-Signal HW Design with KiCad | 8,500 | Fedevel Education, ~$99 USD |
| Book PDFs printing (6 books, selected chapters, ~800 pages total) | 2,500 | ₹3–4/page at photocopy shop |
| NPTEL courses | 0 | Free to audit. Certification optional (~₹1,100/exam if desired) |
| **Courses & books total** | **~₹11,000** | |

### Certification & Compliance Testing (Future — Not Required During Learning)

These costs apply only when you move to **production/commercial sale**. Not needed for prototyping or personal use.

| Item | Cost (₹) | Timeline | Lab |
|------|----------|----------|-----|
| EMC pre-compliance testing | 25,000–50,000 | 1–2 weeks | ETDC Bangalore (STQC, stqc.gov.in/etdc-bengaluru-0) |
| BIS CRS lab testing (if product falls under CRS schedule) | 50,000–1,50,000 | 4–8 weeks | BIS-recognised lab (ETDC, UL India, EMTAC/Vimta Bangalore) |
| BIS CRS application + registration | 10,000–30,000 | 4–12 weeks after test report | Online via BIS portal |
| BIS label review & documentation | 5,000–15,000 | — | — |
| BIS consultant (optional) | 20,000–50,000 | — | HardFault, Om Garuda Group, or similar |
| EMC full compliance (CE/FCC if exporting) | 50,000–2,00,000 | 2–4 weeks | UL Solutions Bangalore, Tata Advanced Systems (Electronics City) |
| **Certification total (per product model)** | **₹85,000–2,50,000** | | |

*Note: BIS CRS certification is compulsory for notified electronic products sold in India. A Jetson carrier board sold as a component/module to B2B customers may not require CRS, but this should be verified with a compliance consultant. Certification renewal is required every 2 years.*

### Total Cost Summary

| Category | ₹ |
|---------|---|
| PCB fabrication & assembly | 37,600 |
| Components | 33,000 |
| Courses & books | 11,000 |
| **Prototyping total** | **~₹81,600** |
| Certification (production only, per model) | 85,000–2,50,000 |
| **Grand total (through production readiness)** | **₹1,65,000–3,30,000** |

---

## Mentorship Touchpoints

| When | Who | What to Bring | Expected Outcome |
|------|-----|--------------|-----------------|
| Week 6 (MP1 done) | Biped hardware expert | PDB schematic + test results | Feedback on power design, soldering quality, test methodology |
| Week 29 (MP5 pre-layout) | Biped hardware expert | STM32 schematic + proposed 4-layer stackup | Catch errors before layout. Advice on USB routing, decoupling strategy |
| Week 40 (MP6 pre-fab) | Biped expert or DESE contact | USB 3.0/GbE layout files | Review differential pair routing and impedance calculations |
| Week 52 (MP8 architecture) | Biped expert + DESE faculty if possible | Architecture spec, block diagram, power tree, BOM | **Most important review.** Architectural errors caught here save entire board re-spins |
| Week 58 (MP9 schematic done) | All available reviewers + NVIDIA forums | Complete carrier board schematic | Final schematic review before committing to 6-layer layout |
| Week 64 (MP10 pre-fab) | Biped expert / DESE | 6-layer layout files | Review high-speed routing, plane continuity, isolation gaps |

---

## Timeline Visualization

```
Month 1:   [Wk 1–4]   MP1: Power Distribution Board ............ 2L
Month 2:   [Wk 5–6]   MP1: Fab + Test
           [Wk 7–8]   MP2: Sensor Board — Theory ............... 2L
Month 3:   [Wk 9–12]  MP2: Design → Fab → Test
Month 4:   [Wk 13–16] MP3: GPS + Battery + DSHOT — Theory+Design  2L
Month 5:   [Wk 17–18] MP3: Fab + Test
           [Wk 19–20] MP4: Integrated Hub — Theory ............. 2L
Month 6:   [Wk 21–24] MP4: Design → Fab → Test
Month 7:   [Wk 25–27] MP5: STM32 FC — Theory (Phil's Lab course) 4L ★
Month 8:   [Wk 28–31] MP5: Design → Review → Layout → Fab
Month 9:   [Wk 32–33] MP5: Assembly → Test → Fly
           [Wk 34–35] MP6: USB+GbE — Theory ................... 4L ★★
Month 10:  [Wk 36–40] MP6: Design → Review → Layout
Month 11:  [Wk 41–44] MP6: Fab → Test → Debug (expect re-spin)
Month 12:  [Wk 45–46] MP7: Camera Board ........................ 4L
           [Wk 47–48] MP8: Reference Design Deep Dive
Month 13:  [Wk 49–52] MP8: Architecture Spec + Review
Month 14:  [Wk 53–56] MP9: Carrier Schematic — Power + SoM + HiSpeed  6L ★★★
Month 15:  [Wk 57–58] MP9: Schematic — I/O + Debug + Review
           [Wk 59–60] MP10: Layout — Stackup + Placement
Month 16:  [Wk 61–64] MP10: Layout — Routing + Review + Fab order
Month 17:  [Wk 65–68] MP11: Bring-Up — Power-on → Boot → Test
Month 18:  [Wk 69–78] MP12: Rev B + Stress Test + Documentation

★ = complexity jump   ★★ = high-speed challenge   ★★★ = the main event
```

---

## What Success Looks Like

**Month 6**: Quadcopter flying on 2 custom boards (PDB + integrated sensor/DSHOT hub). You're fluent in KiCad for 2-layer boards and can read datasheets confidently.

**Month 11**: You've designed 4-layer boards with USB 3.0 SuperSpeed and GbE verified working. You understand controlled impedance routing and can hold a technical conversation with a professional PCB designer.

**Month 13**: You've internalised two production Jetson carrier board designs. You have a complete, reviewed architecture specification for your own board.

**Month 18**: A custom Jetson Orin Nano Super carrier board you designed boots JetPack, with sensor and actuator interfaces tailored for your robotics platform. Rev B is tested and documented. The same board will run your biped's perception and planning software.
