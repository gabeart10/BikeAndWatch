import Toybox.Lang;
import Toybox.System;

typedef GBCPUSendIntFunc as Method(int as GameBoyCPU.IntSrc) as Void;

class GameBoyCPU {
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

    private var _bootRom as ByteArray?;
    private var _hram as ByteArray = new[127]b;
    private var _extBusRead as GBBusRead;
    private var _extBusWrite as GBBusWrite;
    private var _extClockCycle as GBClockCycle;
    private var _state as CPUState = CPU_STATE_RUNNING;
    private var _pc as Number = 0; // Program Counter
    private var _sp as Number = 0; // Stack Pointer
    // Flags use various values to represent on for speed, but off is always 0
    private var _nZFlag as Number = 0; // Not Zero Flag
    private var _NFlag as Number = 0; // Subtract Flag
    private var _HFlag as Number = 0; // Half Carry Flag
    private var _CFlag as Number = 0; // Carry Flag
    private var _ime as Boolean = false; // Interrupt Master Enable Flag
    private var _imeNext as Boolean = false; // Enable IME Next Cycle
    private var _ie as Number = 0; // Interrupt Enable Register
    private var _if as Number = 0; // Interrupt Flag Register
    // Registers: B, C, D, E, H, L, INVALID, A
    private var _regs as Array<Number> = [0, 0, 0, 0, 0, 0, 0, 0];

    private function busRead(addr as Number) as Number {
        // Make sure memory is up to date
        _extClockCycle.invoke(1);

        if (addr == 0xFF50) {
            // BOOT ROM Lock
            return _bootRom != null ? 1 : 0; 
        } else if (addr == 0xFF0F) {
            return _if;
        } else if (addr == 0xFFFF) {
            return _ie;
        } else if (addr >= 0xFF80) {
            // HRAM
            return _hram[addr - 0xFF80];
        } else if (_bootRom != null && addr < 0x100) {
            // During boot, the first 256 bytes of the address space are mapped to the boot ROM
            return _bootRom[addr];
        } else {
            return _extBusRead.invoke(addr);
        }
        return 0xFF;
    }

    private function busWrite(addr as Number, data as Number) as Void {
        // Make sure memory is up to date
        _extClockCycle.invoke(1);

        if (addr == 0xFF50 && data == 0x1) {
            // BOOT ROM Lock
            _bootRom = null; // Lock the boot ROM
        } else if (addr == 0xFF0F) {
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
                throw new Lang.Exception(); // Invalid 16-bit register
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
                throw new Lang.Exception(); // Invalid 16-bit register
        }
    }

    private function calcFlags(firstVal as Number, secondVal as Number, result as Number, isSubtraction as Number, carryMask as Number) as Void {
        _nZFlag = result;
        _NFlag = isSubtraction;
        _HFlag = (firstVal ^ secondVal ^ result) & 0x10;
        _CFlag = result & carryMask;
    }

    function initialize(bootRom as ByteArray, extBusRead as GBBusRead, extBusWrite as GBBusWrite, extClockCycle as GBClockCycle) {
        _bootRom = bootRom;
        _extBusRead = extBusRead;
        _extBusWrite = extBusWrite;
        _extClockCycle = extClockCycle;
    }

    function sendInt(int as IntSrc) as Void {
        _if |= (0x1 << int);
    }

    function bootRomReady() as Boolean {
        return _bootRom != null;
    }

    function step() as Number {
        var mCycles = 1;
        var opcode = OP_NOP;

        // Check for Interrupt
        if (_ime && (_if & _ie) != 0) {
            var if_copy = _if;
            _ime = false;
            for (var bit = 0; bit < INT_END; bit++) {
                if (if_copy & 0x1) {
                    // Clear Interrupt Flag
                    _if &= ~(0x1 << bit);
                    // Push PC to Stack
                    _sp -= 1;
                    cpuBusRequest(_sp, _pc >> 8);
                    _sp -= 1;
                    cpuBusRequest(_sp, _pc & 0xFF);
                    // Set PC to ISR
                    _pc = 0x40 + (bit * 0x8);
                    // Make sure state is correct and add delay
                    _state = CPU_STATE_RUNNING;
                    mCycles += 4;
                }
                if_copy >>= 1;
            } 
        } else {
            switch (_state) {
                case CPU_STATE_RUNNING: {
                    opcode = cpuBusRequest(_pc, null);
                    _pc += 1;
                    break;
                }

                case CPU_STATE_START_HALT: 
                case CPU_STATE_HALTED: {
                    if ((_if & _ie) != 0) {
                        opcode = cpuBusRequest(_pc, null);
                        // Simulate HALT Bug
                        if (_state != CPU_STATE_START_HALT) {
                            _pc += 1;
                        }
                        _state = CPU_STATE_RUNNING;
                    } else {
                        _state = CPU_STATE_HALTED;
                    }
                    break;
                }
            }
        }

        // System.println(
        //     "PC:0x" + _pc.format("%04X")
        //     + " Op: 0x" + opcode.format("%02X")
        //     + " SP:0x" + _sp.format("%04X")
        //     + " A:0x" + _regs[REG_A].format("%02X")
        //     + " B:0x" + _regs[REG_B].format("%02X")
        //     + " C:0x" + _regs[REG_C].format("%02X")
        //     + " D:0x" + _regs[REG_D].format("%02X")
        //     + " E:0x" + _regs[REG_E].format("%02X")
        //     + " H:0x" + _regs[REG_H].format("%02X")
        //     + " L:0x" + _regs[REG_L].format("%02X")
        //     + " Z:" + (_nZFlag == 0 ? "1" : "0")
        //     + " N:" + (_NFlag != 0 ? "1" : "0")
        //     + " H:" + (_HFlag != 0 ? "1" : "0")
        //     + " C:" + (_CFlag != 0 ? "1" : "0")
        // );

        switch (opcode) {
            // ========== Load Instructions ==========
            case OP_LD_A_A:
            case OP_LD_A_B:
            case OP_LD_A_C:
            case OP_LD_A_D:
            case OP_LD_A_E:
            case OP_LD_A_H:
            case OP_LD_A_L:
            case OP_LD_B_B:
            case OP_LD_B_C:
            case OP_LD_B_D:
            case OP_LD_B_E:
            case OP_LD_B_H:
            case OP_LD_B_L:
            case OP_LD_B_A:
            case OP_LD_C_B:
            case OP_LD_C_C:
            case OP_LD_C_D:
            case OP_LD_C_E:
            case OP_LD_C_H:
            case OP_LD_C_L:
            case OP_LD_C_A:
            case OP_LD_D_B:
            case OP_LD_D_C:
            case OP_LD_D_D:
            case OP_LD_D_E:
            case OP_LD_D_H:
            case OP_LD_D_L:
            case OP_LD_D_A:
            case OP_LD_E_B:
            case OP_LD_E_C:
            case OP_LD_E_D:
            case OP_LD_E_E:
            case OP_LD_E_H:
            case OP_LD_E_L:
            case OP_LD_E_A:
            case OP_LD_H_B:
            case OP_LD_H_C:
            case OP_LD_H_D:
            case OP_LD_H_E:
            case OP_LD_H_H:
            case OP_LD_H_L:
            case OP_LD_H_A:
            case OP_LD_L_B:
            case OP_LD_L_C:
            case OP_LD_L_D:
            case OP_LD_L_E:
            case OP_LD_L_H:
            case OP_LD_L_L:
            case OP_LD_L_A: {
                _regs[(opcode >> 3) & 0x07] = _regs[opcode & 0x07];
                break;
            }

            case OP_LD_B_u8:
            case OP_LD_C_u8:
            case OP_LD_D_u8:
            case OP_LD_E_u8:
            case OP_LD_H_u8:
            case OP_LD_L_u8:
            case OP_LD_A_u8: {
                _regs[(opcode >> 3) & 0x07] = cpuBusRequest(_pc, null);
                _pc += 1;
                mCycles += 1;
                break;
            }

            case OP_LD_A_HLptr:
            case OP_LD_B_HLptr:
            case OP_LD_C_HLptr:
            case OP_LD_D_HLptr:
            case OP_LD_E_HLptr:
            case OP_LD_H_HLptr:
            case OP_LD_L_HLptr: {
                _regs[(opcode >> 3) & 0x07] = cpuBusRequest((_regs[REG_H] << 8) | _regs[REG_L], null);
                mCycles += 1;
                break;
            }

            case OP_LD_HLptr_A:
            case OP_LD_HLptr_B:
            case OP_LD_HLptr_C:
            case OP_LD_HLptr_D:
            case OP_LD_HLptr_E:
            case OP_LD_HLptr_H:
            case OP_LD_HLptr_L: {
                cpuBusRequest((_regs[REG_H] << 8) | _regs[REG_L], _regs[opcode & 0x07]);
                mCycles += 1;
                break;
            }

            case OP_LD_HLptr_u8: {
                cpuBusRequest((_regs[REG_H] << 8) | _regs[REG_L], cpuBusRequest(_pc, null));
                _pc += 1;
                mCycles += 2;
                break;
            }

            case OP_LD_A_BCptr: {
                _regs[REG_A] = cpuBusRequest((_regs[REG_B] << 8) | _regs[REG_C], null);
                mCycles += 1;
                break;
            }

            case OP_LD_A_DEptr: {
                _regs[REG_A] = cpuBusRequest((_regs[REG_D] << 8) | _regs[REG_E], null);
                mCycles += 1;
                break;
            }

            case OP_LD_BCptr_A: {
                cpuBusRequest((_regs[REG_B] << 8) | _regs[REG_C], _regs[REG_A]);
                mCycles += 1;
                break;
            }

            case OP_LD_DEptr_A: {
                cpuBusRequest((_regs[REG_D] << 8) | _regs[REG_E], _regs[REG_A]);
                mCycles += 1;
                break;
            }

            case OP_LD_A_u16ptr: {
                var addr = cpuBusRequest(_pc, null) | (cpuBusRequest(_pc + 1, null) << 8);
                _regs[REG_A] = cpuBusRequest(addr, null);
                _pc += 2;
                mCycles += 3;
                break;
            }

            case OP_LD_u16ptr_A: {
                var addr = cpuBusRequest(_pc, null) | (cpuBusRequest(_pc + 1, null) << 8);
                cpuBusRequest(addr, _regs[REG_A]);
                _pc += 2;
                mCycles += 3;
                break;
            }

            case OP_LD_A_Cptr: {
                _regs[REG_A] = cpuBusRequest(0xFF00 | _regs[REG_C], null);
                mCycles += 1;
                break;
            }

            case OP_LD_Cptr_A: {
                cpuBusRequest(0xFF00 | _regs[REG_C], _regs[REG_A]);
                mCycles += 1;
                break;
            }

            case OP_LDH_A_u8ptr: {
                _regs[REG_A] = cpuBusRequest(0xFF00 | cpuBusRequest(_pc, null), null);
                _pc += 1;
                mCycles += 2;
                break;
            }
            
            case OP_LDH_u8ptr_A: {
                cpuBusRequest(0xFF00 | cpuBusRequest(_pc, null), _regs[REG_A]);
                _pc += 1;
                mCycles += 2;
                break;
            }

            case OP_LDI_A_HL:
            case OP_LDD_A_HL: {
                var hl = (_regs[REG_H] << 8) | _regs[REG_L];
                _regs[REG_A] = cpuBusRequest(hl, null);
                if (opcode == OP_LDI_A_HL) {
                    hl += 1;
                } else {
                    hl -= 1;
                }
                _regs[REG_H] = (hl >> 8) & 0xFF;
                _regs[REG_L] = hl & 0xFF;
                mCycles += 1;
                break;
            }

            case OP_LDI_HL_A:
            case OP_LDD_HL_A: {
                var hl = (_regs[REG_H] << 8) | _regs[REG_L];
                cpuBusRequest(hl, _regs[REG_A]);
                if (opcode == OP_LDI_HL_A) {
                    hl += 1;
                } else {
                    hl -= 1;
                }
                _regs[REG_H] = (hl >> 8) & 0xFF;
                _regs[REG_L] = hl & 0xFF;
                mCycles += 1;
                break;
            }


            case OP_LD_BC_u16:
            case OP_LD_DE_u16:
            case OP_LD_HL_u16:
            case OP_LD_SP_u16: {
                var value = cpuBusRequest(_pc, null) | (cpuBusRequest(_pc + 1, null) << 8);
                set16BitReg(((opcode - OP_LD_BC_u16) >> 4) as RegistersEnum, value);
                _pc += 2;
                mCycles += 2;
                break;
            }

            case OP_LD_u16ptr_SP: {
                var addr = cpuBusRequest(_pc, null) | (cpuBusRequest(_pc + 1, null) << 8);
                cpuBusRequest(addr, _sp & 0xFF);
                cpuBusRequest(addr + 1, (_sp >> 8) & 0xFF);
                _pc += 2;
                mCycles += 4;
                break;
            }

            case OP_LD_SP_HL: {
                _sp = (_regs[REG_H] << 8) | _regs[REG_L];
                mCycles += 1;
                break;
            }

            case OP_LD_HL_SP_s8: {
                var offset = (cpuBusRequest(_pc, null) << 24) >> 24; // Convert to 32 bit signed
                var result = _sp + offset;
                _regs[REG_H] = (result >> 8) & 0xFF;
                _regs[REG_L] = result & 0xFF;

                calcFlags(_sp, offset, result, 0, 0x10000);
                _pc += 1;
                mCycles += 2;
                break;
            } 

            // ========== 8-bit Arithmetic Instructions ==========
            case OP_ADD_A:
            case OP_ADD_B:
            case OP_ADD_C:
            case OP_ADD_D:
            case OP_ADD_E:
            case OP_ADD_H:
            case OP_ADD_L: {
                var value = _regs[opcode & 0x07];
                var result = _regs[REG_A] + value;
                calcFlags(_regs[REG_A], value, result, 0, 0x100);
                _regs[REG_A] = result & 0xFF;
                break;
            }

            case OP_ADD_HLptr: {
                var value = cpuBusRequest((_regs[REG_H] << 8) | _regs[REG_L], null);
                var result = _regs[REG_A] + value;
                calcFlags(_regs[REG_A], value, result, 0, 0x100);
                _regs[REG_A] = result & 0xFF;
                mCycles += 1;
                break;
            }

            case OP_ADD_u8: {
                var value = cpuBusRequest(_pc, null);
                var result = _regs[REG_A] + value;
                calcFlags(_regs[REG_A], value, result, 0, 0x100);
                _regs[REG_A] = result & 0xFF;
                _pc += 1;
                mCycles += 1;
                break;
            }

            case OP_ADC_A:
            case OP_ADC_B:
            case OP_ADC_C:
            case OP_ADC_D:
            case OP_ADC_E:
            case OP_ADC_H:
            case OP_ADC_L: {
                var value = _regs[opcode & 0x07];
                var result = _regs[REG_A] + value + (_CFlag ? 1 : 0);
                calcFlags(_regs[REG_A], value, result, 0, 0x100);
                _regs[REG_A] = result & 0xFF;
                break;
            }

            case OP_ADC_HLptr: {
                var value = cpuBusRequest((_regs[REG_H] << 8) | _regs[REG_L], null);
                var result = _regs[REG_A] + value + (_CFlag ? 1 : 0);
                calcFlags(_regs[REG_A], value, result, 0, 0x100);
                _regs[REG_A] = result & 0xFF;
                mCycles += 1;
                break;
            }

            case OP_ADC_u8: {
                var value = cpuBusRequest(_pc, null);
                var result = _regs[REG_A] + value + (_CFlag ? 1 : 0);
                calcFlags(_regs[REG_A], value, result, 0, 0x100);
                _regs[REG_A] = result & 0xFF;
                _pc += 1;
                mCycles += 1;
                break;
            }

            case OP_SUB_A:
            case OP_SUB_B:
            case OP_SUB_C:
            case OP_SUB_D:
            case OP_SUB_E:
            case OP_SUB_H:
            case OP_SUB_L: {
                var value = _regs[opcode & 0x07];
                var result = _regs[REG_A] - value;
                calcFlags(_regs[REG_A], value, result, 1, 0x100);
                _regs[REG_A] = result & 0xFF;
                break;
            }

            case OP_SUB_HLptr: {
                var value = cpuBusRequest((_regs[REG_H] << 8) | _regs[REG_L], null);
                var result = _regs[REG_A] - value;
                calcFlags(_regs[REG_A], value, result, 1, 0x100);
                _regs[REG_A] = result & 0xFF;
                mCycles += 1;
                break;
            }

            case OP_SUB_u8: {
                var value = cpuBusRequest(_pc, null);
                var result = _regs[REG_A] - value;
                calcFlags(_regs[REG_A], value, result, 1, 0x100);
                _regs[REG_A] = result & 0xFF;
                _pc += 1;
                mCycles += 1;
                break;
            }

            case OP_SBC_A:
            case OP_SBC_B:
            case OP_SBC_C:
            case OP_SBC_D:
            case OP_SBC_E:
            case OP_SBC_H:
            case OP_SBC_L: {
                var value = _regs[opcode & 0x07];
                var result = _regs[REG_A] - value - (_CFlag ? 1 : 0);
                calcFlags(_regs[REG_A], value, result, 1, 0x100);
                _regs[REG_A] = result & 0xFF;
                break;
            }

            case OP_SBC_HLptr: {
                var value = cpuBusRequest((_regs[REG_H] << 8) | _regs[REG_L], null);
                var result = _regs[REG_A] - value - (_CFlag ? 1 : 0);
                calcFlags(_regs[REG_A], value, result, 1, 0x100);
                _regs[REG_A] = result & 0xFF;
                mCycles += 1;
                break;
            }

            case OP_SBC_u8: {
                var value = cpuBusRequest(_pc, null);
                var result = _regs[REG_A] - value - (_CFlag ? 1 : 0);
                calcFlags(_regs[REG_A], value, result, 1, 0x100);
                _regs[REG_A] = result & 0xFF;
                _pc += 1;
                mCycles += 1;
                break;
            }

            case OP_CP_A:
            case OP_CP_B:
            case OP_CP_C:
            case OP_CP_D:
            case OP_CP_E:
            case OP_CP_H:
            case OP_CP_L: {
                var value = _regs[opcode & 0x07];
                var result = _regs[REG_A] - value;
                calcFlags(_regs[REG_A], value, result, 1, 0x100);
                break;
            }

            case OP_CP_HLptr: {
                var value = cpuBusRequest((_regs[REG_H] << 8) | _regs[REG_L], null);
                var result = _regs[REG_A] - value;
                calcFlags(_regs[REG_A], value, result, 1, 0x100);
                mCycles += 1;
                break;
            }

            case OP_CP_u8: {
                var value = cpuBusRequest(_pc, null);
                var result = _regs[REG_A] - value;
                calcFlags(_regs[REG_A], value, result, 1, 0x100);
                _pc += 1;
                mCycles += 1;
                break;
            }

            case OP_INC_A:
            case OP_INC_B:
            case OP_INC_C:
            case OP_INC_D:
            case OP_INC_E:
            case OP_INC_H:
            case OP_INC_L: {
                var value = _regs[opcode & 0x07];
                var result = value + 1;
                _nZFlag = result;
                _NFlag = 0;
                _HFlag = (value ^ result) & 0x10;
                _regs[opcode & 0x07] = result & 0xFF;
                break;
            }

            case OP_INC_HLptr: {
                var HL = (_regs[REG_H] << 8) | _regs[REG_L];
                var value = cpuBusRequest(HL, null);
                var result = value + 1;
                _nZFlag = result;
                _NFlag = 0;
                _HFlag = (value ^ result) & 0x10;
                cpuBusRequest(HL, result & 0xFF);
                mCycles += 2;
                break;
            }

            case OP_DEC_A:
            case OP_DEC_B:
            case OP_DEC_C:
            case OP_DEC_D:
            case OP_DEC_E:
            case OP_DEC_H:
            case OP_DEC_L: {
                var value = _regs[opcode & 0x07];
                var result = value - 1;
                _nZFlag = result;
                _NFlag = 0;
                _HFlag = (value ^ result) & 0x10;
                _regs[opcode & 0x07] = result & 0xFF;
                break;
            }

            case OP_DEC_HLptr: {
                var HL = (_regs[REG_H] << 8) | _regs[REG_L];
                var value = cpuBusRequest(HL, null);
                var result = value - 1;
                _nZFlag = result;
                _NFlag = 0;
                _HFlag = (value ^ result) & 0x10;
                cpuBusRequest(HL, result & 0xFF);
                mCycles += 2;
                break;
            }

            // ========== 16-bit Arithmetic Instructions ==========
            case OP_INC_BC:
            case OP_INC_DE:
            case OP_INC_HL:
            case OP_INC_SP: {
                var reg = ((opcode >> 4) & 0x3) as RegistersEnum;
                set16BitReg(reg, get16BitReg(reg) + 1);
                mCycles += 1;
                break;
            }

            case OP_DEC_BC:
            case OP_DEC_DE:
            case OP_DEC_HL:
            case OP_DEC_SP: {
                var reg = ((opcode >> 4) & 0x3) as RegistersEnum;
                set16BitReg(reg, get16BitReg(reg) - 1);
                mCycles += 1;
                break;
            }

            case OP_ADD_HL_BC:
            case OP_ADD_HL_DE:
            case OP_ADD_HL_HL:
            case OP_ADD_HL_SP: {
                var HL = get16BitReg(REG_HL);
                var reg = get16BitReg(((opcode >> 4) & 0x3) as RegistersEnum);
                var result = HL + reg;
                set16BitReg(REG_HL, result);
                _NFlag = 0;
                _HFlag = (HL ^ reg ^ result) & 0x1000;
                _CFlag = result & 0x10000;
                mCycles += 1;
                break;
            }

            // ========== Bitwise Logic Instructions ==========
            case OP_AND_A:
            case OP_AND_B:
            case OP_AND_C:
            case OP_AND_D:
            case OP_AND_E:
            case OP_AND_H:
            case OP_AND_L: {
                _regs[REG_A] &= _regs[opcode & 0x07];
                _nZFlag = _regs[REG_A];
                _NFlag = 0;
                _HFlag = 1;
                _CFlag = 0;
                break;
            }

            case OP_AND_HLptr: {
                _regs[REG_A] &= cpuBusRequest((_regs[REG_H] << 8) | _regs[REG_L], null);
                _nZFlag = _regs[REG_A];
                _NFlag = 0;
                _HFlag = 1;
                _CFlag = 0;
                mCycles += 1;
                break;
            }

            case OP_AND_u8: {
                _regs[REG_A] &= cpuBusRequest(_pc, null);
                _nZFlag = _regs[REG_A];
                _NFlag = 0;
                _HFlag = 1;
                _CFlag = 0;
                _pc += 1;
                mCycles += 1;
                break;
            }

            case OP_XOR_A:
            case OP_XOR_B:
            case OP_XOR_C:
            case OP_XOR_D:
            case OP_XOR_E:
            case OP_XOR_H:
            case OP_XOR_L: {
                _regs[REG_A] ^= _regs[opcode & 0x07];
                _nZFlag = _regs[REG_A];
                _NFlag = 0;
                _HFlag = 0;
                _CFlag = 0;
                break;
            }

            case OP_XOR_HLptr: {
                _regs[REG_A] ^= cpuBusRequest((_regs[REG_H] << 8) | _regs[REG_L], null);
                _nZFlag = _regs[REG_A];
                _NFlag = 0;
                _HFlag = 0;
                _CFlag = 0;
                mCycles += 1;
                break;
            }

            case OP_XOR_u8: {
                _regs[REG_A] ^= cpuBusRequest(_pc, null);
                _nZFlag = _regs[REG_A];
                _NFlag = 0;
                _HFlag = 0;
                _CFlag = 0;
                _pc += 1;
                mCycles += 1;
                break;
            }

            case OP_OR_A:
            case OP_OR_B:
            case OP_OR_C:
            case OP_OR_D:
            case OP_OR_E:
            case OP_OR_H:
            case OP_OR_L: {
                _regs[REG_A] |= _regs[opcode & 0x07];
                _nZFlag = _regs[REG_A];
                _NFlag = 0;
                _HFlag = 0;
                _CFlag = 0;
                break;
            }

            case OP_OR_HLptr: {
                _regs[REG_A] |= cpuBusRequest((_regs[REG_H] << 8) | _regs[REG_L], null);
                _nZFlag = _regs[REG_A];
                _NFlag = 0;
                _HFlag = 0;
                _CFlag = 0;
                mCycles += 1;
                break;
            }

            case OP_OR_u8: {
                _regs[REG_A] |= cpuBusRequest(_pc, null);
                _nZFlag = _regs[REG_A];
                _NFlag = 0;
                _HFlag = 0;
                _CFlag = 0;
                _pc += 1;
                mCycles += 1;
                break;
            }

            case OP_CPL: {
                _regs[REG_A] = ~_regs[REG_A];
                _NFlag = 1;
                _HFlag = 1;
                break;
            }

            // ========== Bit Shift Instructions ==========
            case OP_RLCA: {
                _CFlag = (_regs[REG_A] >> 7) & 0x1;
                _regs[REG_A] = ((_regs[REG_A] << 1) | _CFlag) & 0xFF;
                _nZFlag = 1;
                _NFlag = 0;
                _HFlag = 0;
                break;
            }

            case OP_RRCA: {
                _CFlag = _regs[REG_A] & 0x1;
                _regs[REG_A] = (_regs[REG_A] >> 1) | (_CFlag << 7);
                _nZFlag = 1;
                _NFlag = 0;
                _HFlag = 0;
                break;
            }

            case OP_RLA: {
                var oldCFlag = _CFlag;
                _CFlag = (_regs[REG_A] >> 7) & 0x1;
                _regs[REG_A] = ((_regs[REG_A] << 1) | oldCFlag) & 0xFF;
                _nZFlag = 1;
                _NFlag = 0;
                _HFlag = 0;
                break;
            }

            case OP_RRA: {
                var oldCFlag = _CFlag;
                _CFlag = _regs[REG_A] & 0x1;
                _regs[REG_A] = (_regs[REG_A] >> 1) | (oldCFlag << 7);
                _nZFlag = 1;
                _NFlag = 0;
                _HFlag = 0;
                break;
            }

            case OP_CB_OP: {
                var cbOpcode = cpuBusRequest(_pc, null);
                _pc += 1;
                mCycles += doCBOP(cbOpcode);
                break;
            }

            // ========== Jumps and Subroutine Instructions ==========
            case OP_JP_u16: {
                _pc = (cpuBusRequest(_pc + 1, null) << 8) | cpuBusRequest(_pc, null);
                mCycles += 3;
                break;
            }

            case OP_JP_HL: {
                _pc = get16BitReg(REG_HL);
                break;
            }

            case OP_JP_NZ_u16:
            case OP_JP_Z_u16:
            case OP_JP_NC_u16:
            case OP_JP_C_u16: {
                var cond = false;
                // TODO: Check if we can be slighly inaccurate and not do bus reads on not cond
                var jmpAddr = (cpuBusRequest(_pc + 1, null) << 8) | cpuBusRequest(_pc, null);
                switch ((opcode >> 3) & 0x3) {
                    case JUMP_COND_Z:
                        cond = !_nZFlag;
                        break;
                    case JUMP_COND_NZ:
                        cond = _nZFlag;
                        break;
                    case JUMP_COND_C:
                        cond = _CFlag;
                        break;
                    case JUMP_COND_NZ:
                        cond = !_CFlag;
                        break;
                }

                if (cond) {
                    _pc = jmpAddr;
                    mCycles += 1;
                } else {
                    _pc += 2;
                }
                mCycles += 2;
                break;
            }

            case OP_JR_s8: {
                _pc = (_pc + 1 + ((cpuBusRequest(_pc, null) << 24) >> 24)) & 0xFFFF;
                mCycles += 2;
                break;
            }

            case OP_JR_NZ_s8:
            case OP_JR_Z_s8:
            case OP_JR_NC_s8:
            case OP_JR_C_s8: {
                var cond = false;
                // TODO: Check if we can be slighly inaccurate and not do bus reads on not cond
                var offset = (cpuBusRequest(_pc, null) << 24) >> 24;
                _pc += 1;
                switch ((opcode >> 3) & 0x3) {
                    case JUMP_COND_Z:
                        cond = !_nZFlag;
                        break;
                    case JUMP_COND_NZ:
                        cond = _nZFlag;
                        break;
                    case JUMP_COND_C:
                        cond = _CFlag;
                        break;
                    case JUMP_COND_NZ:
                        cond = !_CFlag;
                        break;
                }

                if (cond) {
                    _pc = (_pc + offset) & 0xFFFF;
                    mCycles += 1;
                }
                mCycles += 1;
                break;
            }

            case OP_CALL_u16: {
                var callAddr = (cpuBusRequest(_pc + 1, null) << 8) | cpuBusRequest(_pc, null);
                _pc += 2;
                _sp -= 1;
                cpuBusRequest(_sp, _pc >> 8);
                _sp -= 1;
                cpuBusRequest(_sp, _pc & 0xFF);
                _pc = callAddr;
                mCycles += 5;
            }

            case OP_CALL_NZ_u16:
            case OP_CALL_Z_u16:
            case OP_CALL_NC_u16:
            case OP_CALL_C_u16: {
                var cond = false;
                // TODO: Check if we can be slighly inaccurate and not do bus reads on not cond
                var callAddr = (cpuBusRequest(_pc + 1, null) << 8) | cpuBusRequest(_pc, null);
                _pc += 2;
                switch ((opcode >> 3) & 0x3) {
                    case JUMP_COND_Z:
                        cond = !_nZFlag;
                        break;
                    case JUMP_COND_NZ:
                        cond = _nZFlag;
                        break;
                    case JUMP_COND_C:
                        cond = _CFlag;
                        break;
                    case JUMP_COND_NZ:
                        cond = !_CFlag;
                        break;
                }

                if (cond) {
                    _sp -= 1;
                    cpuBusRequest(_sp, _pc >> 8);
                    _sp -= 1;
                    cpuBusRequest(_sp, _pc & 0xFF);
                    _pc = callAddr;
                    mCycles += 3;
                }
                mCycles += 2;
                break;
            }


            case OP_RETI:
                _ime = true;
            case OP_RET: {
                _pc = cpuBusRequest(_sp, null);
                _sp += 1;
                _pc |= cpuBusRequest(_sp, null) << 8; 
                _sp += 1;
                mCycles += 3;
                break;
            }

            case OP_RET_NZ:
            case OP_RET_Z:
            case OP_RET_NC:
            case OP_RET_C: {
                var cond = false;
                switch ((opcode >> 3) & 0x3) {
                    case JUMP_COND_Z:
                        cond = !_nZFlag;
                        break;
                    case JUMP_COND_NZ:
                        cond = _nZFlag;
                        break;
                    case JUMP_COND_C:
                        cond = _CFlag;
                        break;
                    case JUMP_COND_NZ:
                        cond = !_CFlag;
                        break;
                }

                if (cond) {
                    _pc = cpuBusRequest(_sp, null);
                    _sp += 1;
                    _pc |= cpuBusRequest(_sp, null) << 8; 
                    _sp += 1;
                    mCycles += 3;
                }
                mCycles += 1;
                break;
            }

            case OP_RST_00H:
            case OP_RST_08H:
            case OP_RST_10H:
            case OP_RST_18H:
            case OP_RST_20H:
            case OP_RST_28H:
            case OP_RST_30H:
            case OP_RST_38H: {
                _sp -= 1;
                cpuBusRequest(_sp, _pc >> 8);
                _sp -= 1;
                cpuBusRequest(_sp, _pc & 0xFF);
                _pc = opcode & 0x38;
                mCycles += 3;
            }

            // ========== Carry Flag Instructions ==========
            case OP_CCF: {
                _NFlag = 0;
                _HFlag = 0;
                _CFlag = !_CFlag;
                break;
            }

            case OP_SCF: {
                _NFlag = 0;
                _HFlag = 0;
                _CFlag = 1;
                break;
            }

            // ========== Stack Manipulation Instructions ==========
            case OP_PUSH_BC:
            case OP_PUSH_DE:
            case OP_PUSH_HL: {
                var pushData = get16BitReg(((opcode >> 4) & 0x3) as RegistersEnum);
                _sp -= 1;
                cpuBusRequest(_sp, pushData >> 8);
                _sp -= 1;
                cpuBusRequest(_sp, pushData & 0xFF);
                mCycles += 3;
            }

            case OP_PUSH_AF: {
                var pushData = _regs[REG_A] << 8;
                pushData |= (!_nZFlag) ? 0x80 : 0x00;
                pushData |= (_NFlag) ? 0x40 : 0x00;
                pushData |= (_HFlag) ? 0x20 : 0x00;
                pushData |= (_CFlag) ? 0x10 : 0x00;
                _sp -= 1;
                cpuBusRequest(_sp, pushData >> 8);
                _sp -= 1;
                cpuBusRequest(_sp, pushData & 0xFF);
                mCycles += 3;
            }

            case OP_POP_BC:
            case OP_POP_DE:
            case OP_POP_HL: {
                var popData = cpuBusRequest(_sp, null);
                _sp += 1;
                popData |= cpuBusRequest(_sp, null) << 8; 
                _sp += 1;
                set16BitReg(((opcode >> 4) & 0x3) as RegistersEnum, popData);
                mCycles += 2;
            }

            case OP_POP_AF: {
                var popData = cpuBusRequest(_sp, null);
                _nZFlag = !(popData & 0x80);
                _NFlag = popData & 0x40;
                _HFlag = popData & 0x20;
                _CFlag = popData & 0x10;
                _sp += 1;
                _regs[REG_A] = cpuBusRequest(_sp, null); 
                _sp += 1;
                mCycles += 2;
            }

            case OP_ADD_SP_s8: {
                var offset = (cpuBusRequest(_pc, null) << 24) >> 24;
                var result = _sp + offset;

                _sp = result & 0xFFFF;
                _nZFlag = 1;
                _NFlag = 0;
                _HFlag = (_sp ^ offset ^ result) & 0x10;
                _CFlag = result & 0x100;

                _pc += 1;
                mCycles += 3;
                break;
            }

            // ========== Interrupt-related Instructions ==========
            case OP_DI: {
                _ime = false;
                _imeNext = false;
                break;
            }

            case OP_EI: {
                _imeNext = true;
                break;
            }

            case OP_HALT: {
                _state = CPU_STATE_START_HALT;
                break;
            }

            // ========== Miscellaneous Instructions ==========
            case OP_DAA: {
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
                    _regs[REG_A] -= adj;
                } else {
                    _regs[REG_A] += adj;
                }
                break;
            }

            case OP_NOP: {
                break;
            }

            // TODO: Implement STOP
            case OP_STOP:
            default:
                throw new Lang.Exception(); // Opcode not implemented
        }

        if (_imeNext && opcode != OP_EI) {
            _imeNext = false;
            _ime = true;
        }

        return mCycles;
    }

    // TODO: Look at if performance gains are worth converting this to one large switch
    private function doCBOP(opcode as Number) as Number {
        var regIndex = opcode & 0x07;
        var opType = (opcode >> 3) & 0x07;
        var group = opcode >> 6;
        var isHL = regIndex == 6;
        var value = isHL ? cpuBusRequest((_regs[REG_H] << 8) | _regs[REG_L], null) : _regs[regIndex];
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
                        var oldC = _CFlag;
                        _CFlag = (value >> 7) & 0x1;
                        result = ((value << 1) | oldC) & 0xFF;
                        break;
                    }

                    case CB_ROT_SHIFT_TYPE_RR: {
                        var oldC = _CFlag;
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

        if (isHL) {
            if (group != CB_GROUP_BIT) { 
                cpuBusRequest((_regs[REG_H] << 8) | _regs[REG_L], result); 
                return 3;
            } else {
                return 2;
            }
        } else {
            if (group != CB_GROUP_BIT) { 
                _regs[regIndex] = result;
            }
            return 1;
        }
    }
}