import Toybox.Lang;
import Toybox.System;

typedef GBCPUSendIntFunc as Method(int as GameBoyCPU.IntSrc) as Void;
typedef GBCPUOp as Method(opcode as Number) as Void;

class GameBoyCPU {
    private enum CBOpcodeGroups {
        CB_GROUP_ROT_SHIFT = 0,
        CB_GROUP_BIT = 1,
        CB_GROUP_RES = 2,
        CB_GROUP_SET = 3,
    }
    private enum CBRotShiftType {
        CB_ROT_SHIFT_TYPE_RLC = 0,
        CB_ROT_SHIFT_TYPE_RRC = 1,
        CB_ROT_SHIFT_TYPE_RL = 2,
        CB_ROT_SHIFT_TYPE_RR = 3,
        CB_ROT_SHIFT_TYPE_SLA = 4,
        CB_ROT_SHIFT_TYPE_SRA = 5,
        CB_ROT_SHIFT_TYPE_SWAP = 6,
        CB_ROT_SHIFT_TYPE_SRL = 7,
    }
    private enum RegistersEnum {
        REG_B = 0,
        REG_C = 1,
        REG_D = 2,
        REG_E = 3,
        REG_H = 4,
        REG_L = 5,
        REG_A = 7,
        REG_BC = 0,
        REG_DE = 1,
        REG_HL = 2,
        REG_SP = 3
    }
    private enum CPUState {
        CPU_STATE_RUNNING = 0,
        CPU_STATE_START_HALT,
        CPU_STATE_HALTED
    }
    enum IntSrc {
        INT_VBLANK = 0,
        INT_LCD = 1,
        INT_TIMER = 2,
        INT_SERIAL = 3,
        INT_JOYPAD = 4,
        INT_END
    }

    private var _skipReadPrint as Boolean = true;
    private var _printEnable as Boolean = false;
    private var _hram as ByteArray = new[127]b;
    private var _extBusRead as GBBusRead;
    private var _extBusWrite as GBBusWrite;
    private var _extClockCycle as GBClockCycle;
    private var _state as CPUState = CPU_STATE_RUNNING;
    private var _pc as Number = 0x100; // Program Counter
    private var _sp as Number = 0xFFFE; // Stack Pointer
    // Flags use various values to represent on for speed, but off is always 0
    private var _nZFlag as Number = 0; // Not Zero Flag
    private var _NFlag as Number = 0; // Subtract Flag
    private var _HFlag as Number = 0; // Half Carry Flag
    private var _CFlag as Number = 0; // Carry Flag
    private var _ime as Boolean = false; // Interrupt Master Enable Flag
    private var _imeNext as Boolean = false; // Enable IME Next Cycle
    private var _ie as Number = 0; // Interrupt Enable Register
    private var _if as Number = 0x1; // Interrupt Flag Register
    // Registers: B, C, D, E, H, L, INVALID, A
    private var _regs as Array<Number> = [0, 0x13, 0, 0xD8, 0x1, 0x4D, 0, 0x1];

    private function busRead(addr as Number) as Number {
        // Make sure memory is up to date
        _extClockCycle.invoke();

        if (PRINT_TRACE) {
            var data = 0xFF;
            if (addr < 0xFF0F) {
                data = _extBusRead.invoke(addr);
            } else {
                if (addr == 0xFF0F) {
                    data = _if;
                } else if (addr == 0xFFFF) {
                    data = _ie;
                } else if (addr >= 0xFF80) {
                    // HRAM
                    data = _hram[addr - 0xFF80];
                } else {
                    data = _extBusRead.invoke(addr);
                }
            }

            if (!_skipReadPrint && _printEnable) {
                System.print(" [0x" + addr.format("%04X") + " 0x" + data.format("%02X") + "]");
            } else {
                _skipReadPrint = false;
            }
            return data;
        } else {
            if (addr < 0xFF0F) {
                return _extBusRead.invoke(addr);
            } else {
                if (addr == 0xFF0F) {
                    return _if | 0xE0;
                } else if (addr == 0xFFFF) {
                    return _ie;
                } else if (addr >= 0xFF80) {
                    // HRAM
                    return _hram[addr - 0xFF80];
                } else {
                    return _extBusRead.invoke(addr);
                }
            }
        }
    }

    private function busWrite(addr as Number, data as Number) as Void {
        // Make sure memory is up to date
        _extClockCycle.invoke();

        if (addr == 0xFF0F) {
            _if = data;
        } else if (addr == 0xFFFF) {
            _ie = data;
        } else if (addr >= 0xFF80) {
            // HRAM
            _hram[addr - 0xFF80] = data;
        } else {
            _extBusWrite.invoke(addr, data);
        }
    }


    private function get16BitReg(reg as RegistersEnum) as Number {
        switch (reg) {
            case REG_BC:
                return (_regs[REG_B] << 8) | _regs[REG_C];
            case REG_DE:
                return (_regs[REG_D] << 8) | _regs[REG_E];
            case REG_HL:
                return (_regs[REG_H] << 8) | _regs[REG_L];
            case REG_SP:
                return _sp;
            default:
                System.println("Invalid 16-bit register: " + reg);
                throw new Lang.Exception();
        }
    }

    private function set16BitReg(reg as RegistersEnum, value as Number) as Void {
        switch (reg) {
            case REG_BC:
                _regs[REG_B] = (value >> 8) & 0xFF;
                _regs[REG_C] = value & 0xFF;
                break;
            case REG_DE:
                _regs[REG_D] = (value >> 8) & 0xFF;
                _regs[REG_E] = value & 0xFF;
                break;
            case REG_HL:
                _regs[REG_H] = (value >> 8) & 0xFF;
                _regs[REG_L] = value & 0xFF;
                break;
            case REG_SP:
                _sp = value & 0xFFFF;
                break;
            default:
                System.println("Invalid 16-bit register: " + reg);
                throw new Lang.Exception();
        }
    }

    private function calcFlags(firstVal as Number, secondVal as Number, result as Number, isSubtraction as Number, carryMask as Number) as Void {
        _nZFlag = result & 0xFF;
        _NFlag = isSubtraction;
        _HFlag = (firstVal ^ secondVal ^ result) & 0x10;
        _CFlag = result & carryMask;
    }

    function initialize(extBusRead as GBBusRead, extBusWrite as GBBusWrite, extClockCycle as GBClockCycle) {
        _extBusRead = extBusRead;
        _extBusWrite = extBusWrite;
        _extClockCycle = extClockCycle;
    }

    function sendInt(int as IntSrc) as Void {
        _if |= (0x1 << int);
    }

    function step() as Void {
        var opcode = 0x00;

        // Check for Interrupt
        if (_ime && (_if & _ie & 0x1F) != 0) {
            var readyInts = _if & _ie;
            _ime = false;
            for (var bit = 0; bit < INT_END; bit++) {
                if (readyInts & 0x1) {
                    // Clear Interrupt Flag
                    _if &= ~(0x1 << bit);
                    // Push PC to Stack
                    _sp--;
                    busWrite(_sp, _pc >> 8);
                    _sp--;
                    busWrite(_sp, _pc & 0xFF);
                    // Set PC to ISR
                    _pc = 0x40 + (bit * 0x8);
                    // Make sure state is correct and add delay
                    _state = CPU_STATE_RUNNING;
                    _extClockCycle.invoke();
                    _extClockCycle.invoke();
                    _extClockCycle.invoke();
                    break;
                }
                readyInts >>= 1;
            } 
        } else {
            switch (_state) {
                case CPU_STATE_RUNNING: {
                    opcode = busRead(_pc);
                    _pc++;
                    break;
                }

                case CPU_STATE_START_HALT: 
                case CPU_STATE_HALTED: {
                    if ((_if & _ie & 0x1F) != 0) {
                        opcode = busRead(_pc);
                        // Simulate HALT Bug
                        if (_state != CPU_STATE_START_HALT) {
                            _pc++;
                        }
                        _state = CPU_STATE_RUNNING;
                    } else {
                        _state = CPU_STATE_HALTED;
                        _extClockCycle.invoke();
                    }
                    break;
                }
            }
        }

        if (PRINT_TRACE) {
            if (_printEnable) {
                System.print(
                    "\n0x" + (_pc - 1).format("%04X")
                    + " " + _opStrings[opcode]
                    + " | SP:0x" + _sp.format("%04X")
                    + " A:0x" + _regs[REG_A].format("%02X")
                    + " B:0x" + _regs[REG_B].format("%02X")
                    + " C:0x" + _regs[REG_C].format("%02X")
                    + " D:0x" + _regs[REG_D].format("%02X")
                    + " E:0x" + _regs[REG_E].format("%02X")
                    + " H:0x" + _regs[REG_H].format("%02X")
                    + " L:0x" + _regs[REG_L].format("%02X")
                    + " Z:" + (_nZFlag == 0 ? "1" : "0")
                    + " N:" + (_NFlag != 0 ? "1" : "0")
                    + " H:" + (_HFlag != 0 ? "1" : "0")
                    + " C:" + (_CFlag != 0 ? "1" : "0")
                );
            }
        }

        // Run opcode function
        _opLookup[opcode].invoke(opcode);

        if (PRINT_TRACE) {
            _skipReadPrint = true;
        }

        // Don't process _imeNext if Op EI just ran
        if (_imeNext && opcode != 0xFB) {
            _imeNext = false;
            _ime = true;
        }
    }

    function op_ld_r_r(opcode as Number) as Void {
        _regs[(opcode >> 3) & 0x07] = _regs[opcode & 0x07];
    }

    function op_ld_r_u8(opcode as Number) as Void {
        _regs[(opcode >> 3) & 0x07] = busRead(_pc);
        _pc++;
    }

    function op_ld_r_HLptr(opcode as Number) as Void {
        _regs[(opcode >> 3) & 0x07] = busRead((_regs[REG_H] << 8) | _regs[REG_L]);
    }

    function op_ld_HLptr_r(opcode as Number) as Void {
        busWrite((_regs[REG_H] << 8) | _regs[REG_L], _regs[opcode & 0x07]);
    }

    function op_ld_HLptr_u8(opcode as Number) as Void {
        busWrite((_regs[REG_H] << 8) | _regs[REG_L], busRead(_pc));
        _pc++;
    }

    function op_ld_A_BCptr(opcode as Number) as Void {
        _regs[REG_A] = busRead((_regs[REG_B] << 8) | _regs[REG_C]);
    }

    function op_ld_A_DEptr(opcode as Number) as Void {
        _regs[REG_A] = busRead((_regs[REG_D] << 8) | _regs[REG_E]);
    }

    function op_ld_BCptr_A(opcode as Number) as Void {
        busWrite((_regs[REG_B] << 8) | _regs[REG_C], _regs[REG_A]);
    }

    function op_ld_DEptr_A(opcode as Number) as Void {
        busWrite((_regs[REG_D] << 8) | _regs[REG_E], _regs[REG_A]);
    }

    function op_ld_A_u16ptr(opcode as Number) as Void {
        var addr = busRead(_pc);
        _pc++;
        addr |= busRead(_pc) << 8;
        _pc++;
        _regs[REG_A] = busRead(addr);
    }

    function op_ld_u16ptr_A(opcode as Number) as Void {
        var addr = busRead(_pc);
        _pc++;
        addr |= busRead(_pc) << 8;
        _pc++;
        busWrite(addr, _regs[REG_A]);
    }

    function op_ld_A_Cptr(opcode as Number) as Void {
        _regs[REG_A] = busRead(0xFF00 | _regs[REG_C]);
    }

    function op_ld_Cptr_A(opcode as Number) as Void {
        busWrite(0xFF00 | _regs[REG_C], _regs[REG_A]);
    }

    function op_ld_A_u8ptr(opcode as Number) as Void {
        _regs[REG_A] = busRead(0xFF00 | busRead(_pc));
        _pc++;
    }
            
    function op_ld_u8ptr_A(opcode as Number) as Void {
        busWrite(0xFF00 | busRead(_pc), _regs[REG_A]);
        _pc++;
    }

    function op_ldi_A_HL(opcode as Number) as Void {
        var hl = (_regs[REG_H] << 8) | _regs[REG_L];
        _regs[REG_A] = busRead(hl);
        hl++;
        _regs[REG_H] = (hl >> 8) & 0xFF;
        _regs[REG_L] = hl & 0xFF;
    }

    function op_ldd_A_HL(opcode as Number) as Void {
        var hl = (_regs[REG_H] << 8) | _regs[REG_L];
        _regs[REG_A] = busRead(hl);
        hl--;
        _regs[REG_H] = (hl >> 8) & 0xFF;
        _regs[REG_L] = hl & 0xFF;
    }

    function op_ldi_HL_A(opcode as Number) as Void {
        var hl = (_regs[REG_H] << 8) | _regs[REG_L];
        busWrite(hl, _regs[REG_A]);
        hl++;
        _regs[REG_H] = (hl >> 8) & 0xFF;
        _regs[REG_L] = hl & 0xFF;
    }

    function op_ldd_HL_A(opcode as Number) as Void {
        var hl = (_regs[REG_H] << 8) | _regs[REG_L];
        busWrite(hl, _regs[REG_A]);
        hl--;
        _regs[REG_H] = (hl >> 8) & 0xFF;
        _regs[REG_L] = hl & 0xFF;
    }

    function op_ld_rr_u16(opcode as Number) as Void {
        var value = busRead(_pc);
        _pc++;
        value |= busRead(_pc) << 8;
        _pc++;
        set16BitReg((opcode >> 4) as RegistersEnum, value);
    }

    function op_ld_u16tr_SP(opcode as Number) as Void {
        var addr = busRead(_pc);
        _pc++;
        addr |= busRead(_pc) << 8;
        _pc++;
        busWrite(addr, _sp & 0xFF);
        busWrite(addr + 1, (_sp >> 8) & 0xFF);
    }

    function op_ld_SP_HL(opcode as Number) as Void {
        _sp = (_regs[REG_H] << 8) | _regs[REG_L];
        _extClockCycle.invoke();
    }

    function op_ld_HL_SP_s8(opcode as Number) as Void {
        var offset = (busRead(_pc) << 24) >> 24; // Convert to 32 bit signed
        var result = _sp + offset;
        _regs[REG_H] = (result >> 8) & 0xFF;
        _regs[REG_L] = result & 0xFF;

        var carry = _sp ^ offset ^ result;
        _nZFlag = 1;
        _NFlag = 0;
        _HFlag = carry & 0x10;
        _CFlag = carry & 0x100;
        _pc++;
        _extClockCycle.invoke();
    } 

    function op_add_r(opcode as Number) as Void {
        var value = _regs[opcode & 0x07];
        var result = _regs[REG_A] + value;
        calcFlags(_regs[REG_A], value, result, 0, 0x100);
        _regs[REG_A] = result & 0xFF;
    }

    function op_add_HLptr(opcode as Number) as Void {
        var value = busRead((_regs[REG_H] << 8) | _regs[REG_L]);
        var result = _regs[REG_A] + value;
        calcFlags(_regs[REG_A], value, result, 0, 0x100);
        _regs[REG_A] = result & 0xFF;
    }

    function op_add_u8(opcode as Number) as Void {
        var value = busRead(_pc);
        var result = _regs[REG_A] + value;
        calcFlags(_regs[REG_A], value, result, 0, 0x100);
        _regs[REG_A] = result & 0xFF;
        _pc++;
    }

    function op_adc_r(opcode as Number) as Void {
        var value = _regs[opcode & 0x07];
        var result = _regs[REG_A] + value + (_CFlag ? 1 : 0);
        calcFlags(_regs[REG_A], value, result, 0, 0x100);
        _regs[REG_A] = result & 0xFF;
    }

    function op_adc_HLptr(opcode as Number) as Void {
        var value = busRead((_regs[REG_H] << 8) | _regs[REG_L]);
        var result = _regs[REG_A] + value + (_CFlag ? 1 : 0);
        calcFlags(_regs[REG_A], value, result, 0, 0x100);
        _regs[REG_A] = result & 0xFF;
    }

    function op_adc_u8(opcode as Number) as Void {
        var value = busRead(_pc);
        var result = _regs[REG_A] + value + (_CFlag ? 1 : 0);
        calcFlags(_regs[REG_A], value, result, 0, 0x100);
        _regs[REG_A] = result & 0xFF;
        _pc++;
    }

    function op_sub_r(opcode as Number) as Void {
        var value = _regs[opcode & 0x07];
        var result = _regs[REG_A] - value;
        calcFlags(_regs[REG_A], value, result, 1, 0x100);
        _regs[REG_A] = result & 0xFF;
    }

    function op_sub_HLptr(opcode as Number) as Void {
        var value = busRead((_regs[REG_H] << 8) | _regs[REG_L]);
        var result = _regs[REG_A] - value;
        calcFlags(_regs[REG_A], value, result, 1, 0x100);
        _regs[REG_A] = result & 0xFF;
    }

    function op_sub_u8(opcode as Number) as Void {
        var value = busRead(_pc);
        var result = _regs[REG_A] - value;
        calcFlags(_regs[REG_A], value, result, 1, 0x100);
        _regs[REG_A] = result & 0xFF;
        _pc++;
    }

    function op_sbc_r(opcode as Number) as Void {
        var value = _regs[opcode & 0x07];
        var result = _regs[REG_A] - value - (_CFlag ? 1 : 0);
        calcFlags(_regs[REG_A], value, result, 1, 0x100);
        _regs[REG_A] = result & 0xFF;
    }

    function op_sbc_HLptr(opcode as Number) as Void {
        var value = busRead((_regs[REG_H] << 8) | _regs[REG_L]);
        var result = _regs[REG_A] - value - (_CFlag ? 1 : 0);
        calcFlags(_regs[REG_A], value, result, 1, 0x100);
        _regs[REG_A] = result & 0xFF;
    }

    function op_sbc_u8(opcode as Number) as Void {
        var value = busRead(_pc);
        var result = _regs[REG_A] - value - (_CFlag ? 1 : 0);
        calcFlags(_regs[REG_A], value, result, 1, 0x100);
        _regs[REG_A] = result & 0xFF;
        _pc++;
    }

    function op_cp_r(opcode as Number) as Void {
        var value = _regs[opcode & 0x07];
        var result = _regs[REG_A] - value;
        calcFlags(_regs[REG_A], value, result, 1, 0x100);
    }

    function op_cp_HLptr(opcode as Number) as Void {
        var value = busRead((_regs[REG_H] << 8) | _regs[REG_L]);
        var result = _regs[REG_A] - value;
        calcFlags(_regs[REG_A], value, result, 1, 0x100);
    }

    function op_cp_u8(opcode as Number) as Void {
        var value = busRead(_pc);
        var result = _regs[REG_A] - value;
        calcFlags(_regs[REG_A], value, result, 1, 0x100);
        _pc++;
    }

    function op_inc_r(opcode as Number) as Void {
        var value = _regs[(opcode >> 3) & 0x07];
        var result = value + 1;
        _nZFlag = result & 0xFF;
        _NFlag = 0;
        _HFlag = (value ^ result) & 0x10;
        _regs[(opcode >> 3) & 0x07] = result & 0xFF;
    }

    function op_inc_HLptr(opcode as Number) as Void {
        var HL = (_regs[REG_H] << 8) | _regs[REG_L];
        var value = busRead(HL);
        var result = value + 1;
        _nZFlag = result & 0xFF;
        _NFlag = 0;
        _HFlag = (value ^ result) & 0x10;
        busWrite(HL, result & 0xFF);
    }

    function op_dec_r(opcode as Number) as Void {
        var value = _regs[(opcode >> 3) & 0x07];
        var result = value - 1;
        _nZFlag = result & 0xFF;
        _NFlag = 1;
        _HFlag = (value ^ result) & 0x10;
        _regs[(opcode >> 3) & 0x07] = result & 0xFF;
    }

    function op_dec_HLptr(opcode as Number) as Void {
        var HL = (_regs[REG_H] << 8) | _regs[REG_L];
        var value = busRead(HL);
        var result = value - 1;
        _nZFlag = result & 0xFF;
        _NFlag = 1;
        _HFlag = (value ^ result) & 0x10;
        busWrite(HL, result & 0xFF);
    }

    function op_inc_rr(opcode as Number) as Void {
        var reg = ((opcode >> 4) & 0x3) as RegistersEnum;
        set16BitReg(reg, get16BitReg(reg) + 1);
        _extClockCycle.invoke();
    }

    function op_dec_rr(opcode as Number) as Void {
        var reg = ((opcode >> 4) & 0x3) as RegistersEnum;
        set16BitReg(reg, get16BitReg(reg) - 1);
        _extClockCycle.invoke();
    }

    function op_add_HL_rr(opcode as Number) as Void {
        var HL = get16BitReg(REG_HL);
        var reg = get16BitReg(((opcode >> 4) & 0x3) as RegistersEnum);
        var result = HL + reg;
        set16BitReg(REG_HL, result);
        _NFlag = 0;
        _HFlag = (HL ^ reg ^ result) & 0x1000;
        _CFlag = result & 0x10000;
        _extClockCycle.invoke();
    }

    function op_and_r(opcode as Number) as Void {
        _regs[REG_A] &= _regs[opcode & 0x07];
        _nZFlag = _regs[REG_A];
        _NFlag = 0;
        _HFlag = 1;
        _CFlag = 0;
    }

    function op_and_HLptr(opcode as Number) as Void {
        _regs[REG_A] &= busRead((_regs[REG_H] << 8) | _regs[REG_L]);
        _nZFlag = _regs[REG_A];
        _NFlag = 0;
        _HFlag = 1;
        _CFlag = 0;
    }

    function op_and_u8(opcode as Number) as Void {
        _regs[REG_A] &= busRead(_pc);
        _nZFlag = _regs[REG_A];
        _NFlag = 0;
        _HFlag = 1;
        _CFlag = 0;
        _pc++;
    }

    function op_xor_r(opcode as Number) as Void {
        _regs[REG_A] ^= _regs[opcode & 0x07];
        _nZFlag = _regs[REG_A];
        _NFlag = 0;
        _HFlag = 0;
        _CFlag = 0;
    }

    function op_xor_HLptr(opcode as Number) as Void {
        _regs[REG_A] ^= busRead((_regs[REG_H] << 8) | _regs[REG_L]);
        _nZFlag = _regs[REG_A];
        _NFlag = 0;
        _HFlag = 0;
        _CFlag = 0;
    }

    function op_xor_u8(opcode as Number) as Void {
        _regs[REG_A] ^= busRead(_pc);
        _nZFlag = _regs[REG_A];
        _NFlag = 0;
        _HFlag = 0;
        _CFlag = 0;
        _pc++;
    }

    function op_or_r(opcode as Number) as Void {
        _regs[REG_A] |= _regs[opcode & 0x07];
        _nZFlag = _regs[REG_A];
        _NFlag = 0;
        _HFlag = 0;
        _CFlag = 0;
    }

    function op_or_HLptr(opcode as Number) as Void {
        _regs[REG_A] |= busRead((_regs[REG_H] << 8) | _regs[REG_L]);
        _nZFlag = _regs[REG_A];
        _NFlag = 0;
        _HFlag = 0;
        _CFlag = 0;
    }

    function op_or_u8(opcode as Number) as Void {
        _regs[REG_A] |= busRead(_pc);
        _nZFlag = _regs[REG_A];
        _NFlag = 0;
        _HFlag = 0;
        _CFlag = 0;
        _pc++;
    }

    function op_cpl(opcode as Number) as Void {
        _regs[REG_A] = (~_regs[REG_A]) & 0xFF;
        _NFlag = 1;
        _HFlag = 1;
    }

    function op_rlca(opcode as Number) as Void {
        _CFlag = (_regs[REG_A] >> 7) & 0x1;
        _regs[REG_A] = ((_regs[REG_A] << 1) | _CFlag) & 0xFF;
        _nZFlag = 1;
        _NFlag = 0;
        _HFlag = 0;
    }

    function op_rrca(opcode as Number) as Void {
        _CFlag = _regs[REG_A] & 0x1;
        _regs[REG_A] = (_regs[REG_A] >> 1) | (_CFlag << 7);
        _nZFlag = 1;
        _NFlag = 0;
        _HFlag = 0;
    }

    function op_rla(opcode as Number) as Void {
        var oldCFlag = (_CFlag) ? 1 : 0;
        _CFlag = (_regs[REG_A] >> 7) & 0x1;
        _regs[REG_A] = ((_regs[REG_A] << 1) | oldCFlag) & 0xFF;
        _nZFlag = 1;
        _NFlag = 0;
        _HFlag = 0;
    }

    function op_rra(opcode as Number) as Void {
        var oldCFlag = (_CFlag) ? 1 : 0;
        _CFlag = _regs[REG_A] & 0x1;
        _regs[REG_A] = (_regs[REG_A] >> 1) | (oldCFlag << 7);
        _nZFlag = 1;
        _NFlag = 0;
        _HFlag = 0;
    }

    function op_cb_op(opcode as Number) as Void {
        opcode = busRead(_pc);
        _pc++;
        doCBOP(opcode);
    }

    function op_jp_u16(opcode as Number) as Void {
        _pc = (busRead(_pc + 1) << 8) | busRead(_pc);
        _extClockCycle.invoke();
    }

    function op_jp_hl(opcode as Number) as Void {
        _pc = get16BitReg(REG_HL);
    }

    function op_jp_nz(opcode as Number) as Void {
        if (_nZFlag) {
            _pc = (busRead(_pc + 1) << 8) | busRead(_pc);
        } else {
            _pc += 2;
            _extClockCycle.invoke();
        }
        _extClockCycle.invoke();
    }

    function op_jp_z(opcode as Number) as Void {
        if (_nZFlag == 0) {
            _pc = (busRead(_pc + 1) << 8) | busRead(_pc);
        } else {
            _pc += 2;
            _extClockCycle.invoke();
        }
        _extClockCycle.invoke();
    }

    function op_jp_nc(opcode as Number) as Void {
        if (_CFlag == 0) {
            _pc = (busRead(_pc + 1) << 8) | busRead(_pc);
        } else {
            _pc += 2;
            _extClockCycle.invoke();
        }
        _extClockCycle.invoke();
    }

    function op_jp_c(opcode as Number) as Void {
        if (_CFlag) {
            _pc = (busRead(_pc + 1) << 8) | busRead(_pc);
        } else {
            _pc += 2;
            _extClockCycle.invoke();
        }
        _extClockCycle.invoke();
    }

    function op_jr_s8(opcode as Number) as Void {
        _pc = (_pc + 1 + ((busRead(_pc) << 24) >> 24)) & 0xFFFF;
        _extClockCycle.invoke();
    }

    function op_jr_nz(opcode as Number) as Void {
        if (_nZFlag) {
            _pc = (_pc + 1 + ((busRead(_pc) << 24) >> 24)) & 0xFFFF;
        } else {
            _pc++;
        }
        _extClockCycle.invoke();
    }

    function op_jr_z(opcode as Number) as Void {
        if (_nZFlag == 0) {
            _pc = (_pc + 1 + ((busRead(_pc) << 24) >> 24)) & 0xFFFF;
        } else {
            _pc++;
        }
        _extClockCycle.invoke();
    }

    function op_jr_nc(opcode as Number) as Void {
        if (_CFlag == 0) {
            _pc = (_pc + 1 + ((busRead(_pc) << 24) >> 24)) & 0xFFFF;
        } else {
            _pc++;
        }
        _extClockCycle.invoke();
    }

    function op_jr_c(opcode as Number) as Void {
        if (_CFlag) {
            _pc = (_pc + 1 + ((busRead(_pc) << 24) >> 24)) & 0xFFFF;
        } else {
            _pc++;
        }
        _extClockCycle.invoke();
    }

    function op_call_u16(opcode as Number) as Void {
        var callAddr = busRead(_pc);
        _pc++;
        callAddr |= busRead(_pc) << 8;
        _pc++;
        _sp--;
        busWrite(_sp, _pc >> 8);
        _sp--;
        busWrite(_sp, _pc & 0xFF);
        _pc = callAddr;
        _extClockCycle.invoke();
    }

    function op_call_nz(opcode as Number) as Void {
        if (_nZFlag) {
            var callAddr = busRead(_pc);
            _pc++;
            callAddr |= busRead(_pc) << 8;
            _pc++;
            _sp--;
            busWrite(_sp, _pc >> 8);
            _sp--;
            busWrite(_sp, _pc & 0xFF);
            _pc = callAddr;
        } else {
            _pc += 2;
            _extClockCycle.invoke();
        }
        _extClockCycle.invoke();
    }

    function op_call_z(opcode as Number) as Void {
        if (_nZFlag == 0) {
            var callAddr = busRead(_pc);
            _pc++;
            callAddr |= busRead(_pc) << 8;
            _pc++;
            _sp--;
            busWrite(_sp, _pc >> 8);
            _sp--;
            busWrite(_sp, _pc & 0xFF);
            _pc = callAddr;
        } else {
            _pc += 2;
            _extClockCycle.invoke();
        }
        _extClockCycle.invoke();
    }

    function op_call_nc(opcode as Number) as Void {
        if (_CFlag == 0) {
            var callAddr = busRead(_pc);
            _pc++;
            callAddr |= busRead(_pc) << 8;
            _pc++;
            _sp--;
            busWrite(_sp, _pc >> 8);
            _sp--;
            busWrite(_sp, _pc & 0xFF);
            _pc = callAddr;
        } else {
            _pc += 2;
            _extClockCycle.invoke();
        }
        _extClockCycle.invoke();
    }

    function op_call_c(opcode as Number) as Void {
        if (_CFlag) {
            var callAddr = busRead(_pc);
            _pc++;
            callAddr |= busRead(_pc) << 8;
            _pc++;
            _sp--;
            busWrite(_sp, _pc >> 8);
            _sp--;
            busWrite(_sp, _pc & 0xFF);
            _pc = callAddr;
        } else {
            _pc += 2;
            _extClockCycle.invoke();
        }
        _extClockCycle.invoke();
    }


    function op_ret_and_reti(opcode as Number) as Void {
        if (opcode & 0x10) {
            _ime = true;
        }
        _pc = busRead(_sp);
        _sp += 1;
        _pc |= busRead(_sp) << 8; 
        _sp += 1;
        _extClockCycle.invoke();
    }

    function op_ret_nz(opcode as Number) as Void {
        if (_nZFlag) {
            _pc = busRead(_sp);
            _sp += 1;
            _pc |= busRead(_sp) << 8; 
            _sp += 1;
            _extClockCycle.invoke();
        }
        _extClockCycle.invoke();
    }

    function op_ret_z(opcode as Number) as Void {
        if (_nZFlag == 0) {
            _pc = busRead(_sp);
            _sp += 1;
            _pc |= busRead(_sp) << 8; 
            _sp += 1;
            _extClockCycle.invoke();
        }
        _extClockCycle.invoke();
    }

    function op_ret_nc(opcode as Number) as Void {
        if (_CFlag == 0) {
            _pc = busRead(_sp);
            _sp += 1;
            _pc |= busRead(_sp) << 8; 
            _sp += 1;
            _extClockCycle.invoke();
        }
        _extClockCycle.invoke();
    }

    function op_ret_c(opcode as Number) as Void {
        if (_CFlag) {
            _pc = busRead(_sp);
            _sp += 1;
            _pc |= busRead(_sp) << 8; 
            _sp += 1;
            _extClockCycle.invoke();
        }
        _extClockCycle.invoke();
    }

    function op_rst(opcode as Number) as Void {
        _sp -= 1;
        busWrite(_sp, _pc >> 8);
        _sp -= 1;
        busWrite(_sp, _pc & 0xFF);
        _pc = opcode & 0x38;
        _extClockCycle.invoke();
    }

    function op_ccf(opcode as Number) as Void {
        _NFlag = 0;
        _HFlag = 0;
        _CFlag = (_CFlag == 0) ? 1 : 0;
    }

    function op_scf(opcode as Number) as Void {
        _NFlag = 0;
        _HFlag = 0;
        _CFlag = 1;
    }

    function op_push_rr(opcode as Number) as Void {
        var pushData = get16BitReg(((opcode >> 4) & 0x3) as RegistersEnum);
        _sp -= 1;
        busWrite(_sp, pushData >> 8);
        _sp -= 1;
        busWrite(_sp, pushData & 0xFF);
        _extClockCycle.invoke();
    }

    function op_push_AF(opcode as Number) as Void {
        var pushData = _regs[REG_A] << 8;
        pushData |= (_nZFlag == 0) ? 0x80 : 0x00;
        pushData |= (_NFlag) ? 0x40 : 0x00;
        pushData |= (_HFlag) ? 0x20 : 0x00;
        pushData |= (_CFlag) ? 0x10 : 0x00;
        _sp -= 1;
        busWrite(_sp, pushData >> 8);
        _sp -= 1;
        busWrite(_sp, pushData & 0xFF);
        _extClockCycle.invoke();
    }

    function op_pop_rr(opcode as Number) as Void {
        var popData = busRead(_sp);
        _sp += 1;
        popData |= busRead(_sp) << 8; 
        _sp += 1;
        set16BitReg(((opcode >> 4) & 0x3) as RegistersEnum, popData);
    }

    function op_pop_AF(opcode as Number) as Void {
        var popData = busRead(_sp);
        _nZFlag = ((popData & 0x80) == 0) ? 1 : 0;
        _NFlag = popData & 0x40;
        _HFlag = popData & 0x20;
        _CFlag = popData & 0x10;
        _sp += 1;
        _regs[REG_A] = busRead(_sp); 
        _sp += 1;
    }

    function op_add_SP_s8(opcode as Number) as Void {
        var offset = (busRead(_pc) << 24) >> 24;
        var result = _sp + offset;

        var carry = _sp ^ offset ^ result;
        _nZFlag = 1;
        _NFlag = 0;
        _HFlag = carry & 0x10;
        _CFlag = carry & 0x100;

        _sp = result & 0xFFFF;
        _pc++;
        _extClockCycle.invoke();
        _extClockCycle.invoke();
    }

    function op_di(opcode as Number) as Void {
        _ime = false;
        _imeNext = false;
    }

    function op_ei(opcode as Number) as Void {
        _imeNext = true;
    }

    function op_halt(opcode as Number) as Void {
        _state = CPU_STATE_START_HALT;
    }

    function op_daa(opcode as Number) as Void {
        var adj = 0;
        if ((_HFlag != 0) || ((_NFlag == 0) && ((_regs[REG_A] & 0xF) > 0x9))) {
            adj += 0x6;
        }
        if ((_CFlag != 0) || ((_NFlag == 0) && (_regs[REG_A] > 0x99))) {
            adj += 0x60;
            if (_NFlag == 0) {
                _CFlag = 1;
            }
        }
        if (_NFlag != 0) {
            _regs[REG_A] = (_regs[REG_A] - adj) & 0xFF;
        } else {
            _regs[REG_A] = (_regs[REG_A] + adj) & 0xFF;
        }
        _nZFlag = _regs[REG_A]; 
        _HFlag = 0;
    }

    function op_nop(opcode as Number) as Void {
    }

    function op_invalid(opcode as Number) as Void {
        System.println("Opcode not implemented: 0x" + opcode.format("%02X"));
        throw new Lang.Exception();
    }

    // TODO: Look at if performance gains are worth converting this to per op functions
    private function doCBOP(opcode as Number) as Void {
        var regIndex = opcode & 0x07;
        var opType = (opcode >> 3) & 0x07;
        var group = opcode >> 6;
        var isHL = regIndex == 6;
        var value = isHL ? busRead((_regs[REG_H] << 8) | _regs[REG_L]) : _regs[regIndex];
        var result = 0;

        switch (group) {
            case CB_GROUP_ROT_SHIFT: {
                switch (opType) {
                    case CB_ROT_SHIFT_TYPE_RLC: {
                        _CFlag = (value >> 7) & 0x1;
                        result = ((value << 1) | _CFlag) & 0xFF;
                        break;
                    }

                    case CB_ROT_SHIFT_TYPE_RRC: {
                        _CFlag = value & 0x1;
                        result = (value >> 1) | (_CFlag << 7);
                        break;
                    }

                    case CB_ROT_SHIFT_TYPE_RL: {
                        var oldC = (_CFlag) ? 1 : 0;
                        _CFlag = (value >> 7) & 0x1;
                        result = ((value << 1) | oldC) & 0xFF;
                        break;
                    }

                    case CB_ROT_SHIFT_TYPE_RR: {
                        var oldC = (_CFlag) ? 1 : 0;
                        _CFlag = value & 0x1;
                        result = (value >> 1) | (oldC << 7);
                        break;
                    }

                    case CB_ROT_SHIFT_TYPE_SLA: {
                        _CFlag = (value >> 7) & 0x1;
                        result = (value << 1) & 0xFF;
                        break;
                    }

                    case CB_ROT_SHIFT_TYPE_SRA: {
                        _CFlag = value & 0x1;
                        result = (value >> 1) | (value & 0x80);
                        break;
                    }

                    case CB_ROT_SHIFT_TYPE_SWAP: {
                        _CFlag = 0;
                        result = ((value << 4) & 0xF0) | (value >> 4);
                        break;
                    }

                    case CB_ROT_SHIFT_TYPE_SRL: {
                        _CFlag = value & 0x1;
                        result = value >> 1;
                        break;
                    }
                }
                _nZFlag = result;
                _NFlag = 0;
                _HFlag = 0;
                break;
            }

            case CB_GROUP_BIT: {
                _nZFlag = (value >> opType) & 0x1;
                _NFlag = 0;
                _HFlag = 1;
                break;
            }

            case CB_GROUP_RES: {
                result = value & ~(1 << opType);
                break;
            }

            case CB_GROUP_SET: {
                result = value | (1 << opType);
                break;
            }
        }

        if (group != CB_GROUP_BIT) { 
            if (isHL) {
                busWrite((_regs[REG_H] << 8) | _regs[REG_L], result); 
            } else {
                _regs[regIndex] = result;
            }
        }
    }

    private var _opLookup as Array<GBCPUOp> = [
        method(:op_nop),
        method(:op_ld_rr_u16),
        method(:op_ld_BCptr_A),
        method(:op_inc_rr),
        method(:op_inc_r),
        method(:op_dec_r),
        method(:op_ld_r_u8),
        method(:op_rlca),
        method(:op_ld_u16tr_SP),
        method(:op_add_HL_rr),
        method(:op_ld_A_BCptr),
        method(:op_dec_rr),
        method(:op_inc_r),
        method(:op_dec_r),
        method(:op_ld_r_u8),
        method(:op_rrca),
        method(:op_invalid),
        method(:op_ld_rr_u16),
        method(:op_ld_DEptr_A),
        method(:op_inc_rr),
        method(:op_inc_r),
        method(:op_dec_r),
        method(:op_ld_r_u8),
        method(:op_rla),
        method(:op_jr_s8),
        method(:op_add_HL_rr),
        method(:op_ld_A_DEptr),
        method(:op_dec_rr),
        method(:op_inc_r),
        method(:op_dec_r),
        method(:op_ld_r_u8),
        method(:op_rra),
        method(:op_jr_nz),
        method(:op_ld_rr_u16),
        method(:op_ldi_HL_A),
        method(:op_inc_rr),
        method(:op_inc_r),
        method(:op_dec_r),
        method(:op_ld_r_u8),
        method(:op_daa),
        method(:op_jr_z),
        method(:op_add_HL_rr),
        method(:op_ldi_A_HL),
        method(:op_dec_rr),
        method(:op_inc_r),
        method(:op_dec_r),
        method(:op_ld_r_u8),
        method(:op_cpl),
        method(:op_jr_nc),
        method(:op_ld_rr_u16),
        method(:op_ldd_HL_A),
        method(:op_inc_rr),
        method(:op_inc_HLptr),
        method(:op_dec_HLptr),
        method(:op_ld_HLptr_u8),
        method(:op_scf),
        method(:op_jr_c),
        method(:op_add_HL_rr),
        method(:op_ldd_A_HL),
        method(:op_dec_rr),
        method(:op_inc_r),
        method(:op_dec_r),
        method(:op_ld_r_u8),
        method(:op_ccf),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_HLptr),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_HLptr),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_HLptr),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_HLptr),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_HLptr),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_HLptr),
        method(:op_ld_r_r),
        method(:op_ld_HLptr_r),
        method(:op_ld_HLptr_r),
        method(:op_ld_HLptr_r),
        method(:op_ld_HLptr_r),
        method(:op_ld_HLptr_r),
        method(:op_ld_HLptr_r),
        method(:op_halt),
        method(:op_ld_HLptr_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_r),
        method(:op_ld_r_HLptr),
        method(:op_ld_r_r),
        method(:op_add_r),
        method(:op_add_r),
        method(:op_add_r),
        method(:op_add_r),
        method(:op_add_r),
        method(:op_add_r),
        method(:op_add_HLptr),
        method(:op_add_r),
        method(:op_adc_r),
        method(:op_adc_r),
        method(:op_adc_r),
        method(:op_adc_r),
        method(:op_adc_r),
        method(:op_adc_r),
        method(:op_adc_HLptr),
        method(:op_adc_r),
        method(:op_sub_r),
        method(:op_sub_r),
        method(:op_sub_r),
        method(:op_sub_r),
        method(:op_sub_r),
        method(:op_sub_r),
        method(:op_sub_HLptr),
        method(:op_sub_r),
        method(:op_sbc_r),
        method(:op_sbc_r),
        method(:op_sbc_r),
        method(:op_sbc_r),
        method(:op_sbc_r),
        method(:op_sbc_r),
        method(:op_sbc_HLptr),
        method(:op_sbc_r),
        method(:op_and_r),
        method(:op_and_r),
        method(:op_and_r),
        method(:op_and_r),
        method(:op_and_r),
        method(:op_and_r),
        method(:op_and_HLptr),
        method(:op_and_r),
        method(:op_xor_r),
        method(:op_xor_r),
        method(:op_xor_r),
        method(:op_xor_r),
        method(:op_xor_r),
        method(:op_xor_r),
        method(:op_xor_HLptr),
        method(:op_xor_r),
        method(:op_or_r),
        method(:op_or_r),
        method(:op_or_r),
        method(:op_or_r),
        method(:op_or_r),
        method(:op_or_r),
        method(:op_or_HLptr),
        method(:op_or_r),
        method(:op_cp_r),
        method(:op_cp_r),
        method(:op_cp_r),
        method(:op_cp_r),
        method(:op_cp_r),
        method(:op_cp_r),
        method(:op_cp_HLptr),
        method(:op_cp_r),
        method(:op_ret_nz),
        method(:op_pop_rr),
        method(:op_jp_nz),
        method(:op_jp_u16),
        method(:op_call_nz),
        method(:op_push_rr),
        method(:op_add_u8),
        method(:op_rst),
        method(:op_ret_z),
        method(:op_ret_and_reti),
        method(:op_jp_z),
        method(:op_cb_op),
        method(:op_call_z),
        method(:op_call_u16),
        method(:op_adc_u8),
        method(:op_rst),
        method(:op_ret_nc),
        method(:op_pop_rr),
        method(:op_jp_nc),
        method(:op_invalid),
        method(:op_call_nc),
        method(:op_push_rr),
        method(:op_sub_u8),
        method(:op_rst),
        method(:op_ret_c),
        method(:op_ret_and_reti),
        method(:op_jp_c),
        method(:op_invalid),
        method(:op_call_c),
        method(:op_invalid),
        method(:op_sbc_u8),
        method(:op_rst),
        method(:op_ld_u8ptr_A),
        method(:op_pop_rr),
        method(:op_ld_Cptr_A),
        method(:op_invalid),
        method(:op_invalid),
        method(:op_push_rr),
        method(:op_and_u8),
        method(:op_rst),
        method(:op_add_SP_s8),
        method(:op_jp_hl),
        method(:op_ld_u16ptr_A),
        method(:op_invalid),
        method(:op_invalid),
        method(:op_invalid),
        method(:op_xor_u8),
        method(:op_rst),
        method(:op_ld_A_u8ptr),
        method(:op_pop_AF),
        method(:op_ld_A_Cptr),
        method(:op_di),
        method(:op_invalid),
        method(:op_push_AF),
        method(:op_or_u8),
        method(:op_rst),
        method(:op_ld_HL_SP_s8),
        method(:op_ld_SP_HL),
        method(:op_ld_A_u16ptr),
        method(:op_ei),
        method(:op_invalid),
        method(:op_invalid),
        method(:op_cp_u8),
        method(:op_rst),
    ];

    private const _opStrings as Array<String> = [
        "NOP        ",
        "LD BC,d16  ",
        "LD (BC),A  ",
        "INC BC     ",
        "INC B      ",
        "DEC B      ",
        "LD B,d8    ",
        "RLCA       ",
        "LD (a16),SP",
        "ADD HL,BC  ",
        "LD A,(BC)  ",
        "DEC BC     ",
        "INC C      ",
        "DEC C      ",
        "LD C,d8    ",
        "RRCA       ",
        "STOP       ",
        "LD DE,d16  ",
        "LD (DE),A  ",
        "INC DE     ",
        "INC D      ",
        "DEC D      ",
        "LD D,d8    ",
        "RLA        ",
        "JR r8      ",
        "ADD HL,DE  ",
        "LD A,(DE)  ",
        "DEC DE     ",
        "INC E      ",
        "DEC E      ",
        "LD E,d8    ",
        "RRA        ",
        "JR NZ,r8   ",
        "LD HL,d16  ",
        "LDI (HL),A ",
        "INC HL     ",
        "INC H      ",
        "DEC H      ",
        "LD H,d8    ",
        "DAA        ",
        "JR Z,r8    ",
        "ADD HL,HL  ",
        "LDI A,(HL) ",
        "DEC HL     ",
        "INC L      ",
        "DEC L      ",
        "LD L,d8    ",
        "CPL        ",
        "JR NC,r8   ",
        "LD SP,d16  ",
        "LDD (HL),A ",
        "INC SP     ",
        "INC (HL)   ",
        "DEC (HL)   ",
        "LD (HL),d8 ",
        "SCF        ",
        "JR C,r8    ",
        "ADD HL,SP  ",
        "LDD A,(HL) ",
        "DEC SP     ",
        "INC A      ",
        "DEC A      ",
        "LD A,d8    ",
        "CCF        ",
        "LD B,B     ",
        "LD B,C     ",
        "LD B,D     ",
        "LD B,E     ",
        "LD B,H     ",
        "LD B,L     ",
        "LD B,(HL)  ",
        "LD B,A     ",
        "LD C,B     ",
        "LD C,C     ",
        "LD C,D     ",
        "LD C,E     ",
        "LD C,H     ",
        "LD C,L     ",
        "LD C,(HL)  ",
        "LD C,A     ",
        "LD D,B     ",
        "LD D,C     ",
        "LD D,D     ",
        "LD D,E     ",
        "LD D,H     ",
        "LD D,L     ",
        "LD D,(HL)  ",
        "LD D,A     ",
        "LD E,B     ",
        "LD E,C     ",
        "LD E,D     ",
        "LD E,E     ",
        "LD E,H     ",
        "LD E,L     ",
        "LD E,(HL)  ",
        "LD E,A     ",
        "LD H,B     ",
        "LD H,C     ",
        "LD H,D     ",
        "LD H,E     ",
        "LD H,H     ",
        "LD H,L     ",
        "LD H,(HL)  ",
        "LD H,A     ",
        "LD L,B     ",
        "LD L,C     ",
        "LD L,D     ",
        "LD L,E     ",
        "LD L,H     ",
        "LD L,L     ",
        "LD L,(HL)  ",
        "LD L,A     ",
        "LD (HL),B  ",
        "LD (HL),C  ",
        "LD (HL),D  ",
        "LD (HL),E  ",
        "LD (HL),H  ",
        "LD (HL),L  ",
        "HALT       ",
        "LD (HL),A  ",
        "LD A,B     ",
        "LD A,C     ",
        "LD A,D     ",
        "LD A,E     ",
        "LD A,H     ",
        "LD A,L     ",
        "LD A,(HL)  ",
        "LD A,A     ",
        "ADD A,B    ",
        "ADD A,C    ",
        "ADD A,D    ",
        "ADD A,E    ",
        "ADD A,H    ",
        "ADD A,L    ",
        "ADD A,(HL) ",
        "ADD A,A    ",
        "ADC A,B    ",
        "ADC A,C    ",
        "ADC A,D    ",
        "ADC A,E    ",
        "ADC A,H    ",
        "ADC A,L    ",
        "ADC A,(HL) ",
        "ADC A,A    ",
        "SUB B      ",
        "SUB C      ",
        "SUB D      ",
        "SUB E      ",
        "SUB H      ",
        "SUB L      ",
        "SUB (HL)   ",
        "SUB A      ",
        "SBC A,B    ",
        "SBC A,C    ",
        "SBC A,D    ",
        "SBC A,E    ",
        "SBC A,H    ",
        "SBC A,L    ",
        "SBC A,(HL) ",
        "SBC A,A    ",
        "AND B      ",
        "AND C      ",
        "AND D      ",
        "AND E      ",
        "AND H      ",
        "AND L      ",
        "AND (HL)   ",
        "AND A      ",
        "XOR B      ",
        "XOR C      ",
        "XOR D      ",
        "XOR E      ",
        "XOR H      ",
        "XOR L      ",
        "XOR (HL)   ",
        "XOR A      ",
        "OR B       ",
        "OR C       ",
        "OR D       ",
        "OR E       ",
        "OR H       ",
        "OR L       ",
        "OR (HL)    ",
        "OR A       ",
        "CP B       ",
        "CP C       ",
        "CP D       ",
        "CP E       ",
        "CP H       ",
        "CP L       ",
        "CP (HL)    ",
        "CP A       ",
        "RET NZ     ",
        "POP BC     ",
        "JP NZ,a16  ",
        "JP a16     ",
        "CALL NZ,a16",
        "PUSH BC    ",
        "ADD A,d8   ",
        "RST 00H    ",
        "RET Z      ",
        "RET        ",
        "JP Z,a16   ",
        "CB         ",
        "CALL Z,a16 ",
        "CALL a16   ",
        "ADC A,d8   ",
        "RST 08H    ",
        "RET NC     ",
        "POP DE     ",
        "JP NC,a16  ",
        "INVALID    ",
        "CALL NC,a16",
        "PUSH DE    ",
        "SUB d8     ",
        "RST 10H    ",
        "RET C      ",
        "RETI       ",
        "JP C,a16   ",
        "INVALID    ",
        "CALL C,a16 ",
        "INVALID    ",
        "SBC A,d8   ",
        "RST 18H    ",
        "LDH (a8),A ",
        "POP HL     ",
        "LD (C),A   ",
        "INVALID    ",
        "INVALID    ",
        "PUSH HL    ",
        "AND d8     ",
        "RST 20H    ",
        "ADD SP,r8  ",
        "JP HL      ",
        "LD (a16),A ",
        "INVALID    ",
        "INVALID    ",
        "INVALID    ",
        "XOR d8     ",
        "RST 28H    ",
        "LDH A,(a8) ",
        "POP AF     ",
        "LD A,(C)   ",
        "DI         ",
        "INVALID    ",
        "PUSH AF    ",
        "OR d8      ",
        "RST 30H    ",
        "LD HL,SP+r8",
        "LD SP,HL   ",
        "LD A,(a16) ",
        "EI         ",
        "INVALID    ",
        "INVALID    ",
        "CP d8      ",
        "RST 38H    ",
    ];
}