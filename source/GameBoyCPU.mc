import Toybox.Lang;

class GameBoyCPU {
    private var _bootRom as ByteArray?;
    private var _busRequest as BusRequestFunc;
    private var _pc as Number = 0; // Program Counter
    private var _sp as Number = 0; // Stack Pointer
    private var _ZFlag as Number = 0; // Zero Flag
    private var _NFlag as Number = 0; // Subtract Flag
    private var _HFlag as Number = 0; // Half Carry Flag
    private var _CFlag as Number = 0; // Carry Flag
    private var _ie as Number = 0; // Interrupt Enable Register
    // Registers: B, C, D, E, H, L, INVALID, A
    private var _regs as Array<Number> = [0, 0, 0, 0, 0, 0, 0, 0];
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

    private function cpuBusRequest(addr as Number, data as Number?) as Number {
        if (addr == 0xFF50) {
            // BOOT ROM Lock
            if (data == 1) {
                _bootRom = null; // Lock the boot ROM
            } else if (data == null) {
                return _bootRom != null ? 1 : 0; 
            }
        } else if (_bootRom != null && addr < 0x100 && data == null) {
            // During boot, the first 256 bytes of the address space are mapped to the boot ROM
            return _bootRom[addr];
        } else {
            return _busRequest.invoke(addr, data);
        }
        return 0xFF;
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

    function initialize(bootRom as ByteArray, busRequest as BusRequestFunc) {
        _bootRom = bootRom;
        _busRequest = busRequest;
    }

    function bootRomReady() as Boolean {
        return _bootRom != null;
    }

    function step() as Number {
        var mCycles = 1;
        var opcode = cpuBusRequest(_pc, null);
        _pc += 1;

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
                var offset = cpuBusRequest(_pc, null);
                if (offset >= 0x80) {
                    offset = -((~offset + 1) & 0xFF); // Convert to signed
                }
                var result = (_sp + offset) & 0xFFFF;
                _regs[REG_H] = (result >> 8) & 0xFF;
                _regs[REG_L] = result & 0xFF;

                // Set flags
                _ZFlag = 0;
                _NFlag = 0;
                // Might be a better way to calc Half Carry
                _HFlag = ((_sp & 0xF) + (offset & 0xF)) > 0xF ? 1 : 0;
                _CFlag = (result > 0xFF) ? 1 : 0;

                _pc += 1;
                mCycles += 2;
                break;
            } 

            // ========== 8-bit Arithmetic Instructions ==========
            case OP_ADD_B:
            case OP_ADD_C:
            case OP_ADD_D:
            case OP_ADD_E:
            case OP_ADD_H:
            case OP_ADD_L:
            case OP_ADD_HLptr:
            case OP_ADD_A:
            case OP_ADD_u8:
            case OP_ADC_B:
            case OP_ADC_C:
            case OP_ADC_D:
            case OP_ADC_E:
            case OP_ADC_H:
            case OP_ADC_L:
            case OP_ADC_HLptr:
            case OP_ADC_A:
            case OP_ADC_u8:
            case OP_SUB_B:
            case OP_SUB_C:
            case OP_SUB_D:
            case OP_SUB_E:
            case OP_SUB_H:
            case OP_SUB_L:
            case OP_SUB_HLptr:
            case OP_SUB_A:
            case OP_SUB_u8:
            case OP_SBC_B:
            case OP_SBC_C:
            case OP_SBC_D:
            case OP_SBC_E:
            case OP_SBC_H:
            case OP_SBC_L:
            case OP_SBC_HLptr:
            case OP_SBC_A:
            case OP_SBC_u8:
            case OP_CP_B:
            case OP_CP_C:
            case OP_CP_D:
            case OP_CP_E:
            case OP_CP_H:
            case OP_CP_L:
            case OP_CP_HLptr:
            case OP_CP_A:
            case OP_CP_u8:
            case OP_INC_B:
            case OP_INC_C:
            case OP_INC_D:
            case OP_INC_E:
            case OP_INC_H:
            case OP_INC_L:
            case OP_INC_HLptr:
            case OP_INC_A:
            case OP_DEC_B:
            case OP_DEC_C:
            case OP_DEC_D:
            case OP_DEC_E:
            case OP_DEC_H:
            case OP_DEC_L:
            case OP_DEC_HLptr:
            case OP_DEC_A:
                // TODO: Implement 8-bit arithmetic instructions
                break;

            // ========== 16-bit Arithmetic Instructions ==========
            case OP_ADD_HL_BC:
            case OP_ADD_HL_DE:
            case OP_ADD_HL_HL:
            case OP_ADD_HL_SP:
            case OP_INC_BC:
            case OP_INC_DE:
            case OP_INC_HL:
            case OP_INC_SP:
            case OP_DEC_BC:
            case OP_DEC_DE:
            case OP_DEC_HL:
            case OP_DEC_SP:
                // TODO: Implement 16-bit arithmetic instructions
                break;

            // ========== Bitwise Logic Instructions ==========
            case OP_AND_B:
            case OP_AND_C:
            case OP_AND_D:
            case OP_AND_E:
            case OP_AND_H:
            case OP_AND_L:
            case OP_AND_HLptr:
            case OP_AND_A:
            case OP_AND_u8:
            case OP_XOR_B:
            case OP_XOR_C:
            case OP_XOR_D:
            case OP_XOR_E:
            case OP_XOR_H:
            case OP_XOR_L:
            case OP_XOR_HLptr:
            case OP_XOR_A:
            case OP_XOR_u8:
            case OP_OR_B:
            case OP_OR_C:
            case OP_OR_D:
            case OP_OR_E:
            case OP_OR_H:
            case OP_OR_L:
            case OP_OR_HLptr:
            case OP_OR_A:
            case OP_OR_u8:
            case OP_CPL:
                // TODO: Implement bitwise logic instructions
                break;

            // ========== Bit Shift Instructions ==========
            case OP_RLCA:
            case OP_RLA:
            case OP_RRCA:
            case OP_RRA:
            case OP_CB_OP:
                // TODO: Implement bit shift instructions (CB-prefixed)
                break;

            // ========== Jumps and Subroutine Instructions ==========
            case OP_JP_u16:
            case OP_JP_HL:
            case OP_JP_NZ_u16:
            case OP_JP_Z_u16:
            case OP_JP_NC_u16:
            case OP_JP_C_u16:
            case OP_JR_s8:
            case OP_JR_NZ_s8:
            case OP_JR_Z_s8:
            case OP_JR_NC_s8:
            case OP_JR_C_s8:
            case OP_CALL_u16:
            case OP_CALL_NZ_u16:
            case OP_CALL_Z_u16:
            case OP_CALL_NC_u16:
            case OP_CALL_C_u16:
            case OP_RET:
            case OP_RET_NZ:
            case OP_RET_Z:
            case OP_RET_NC:
            case OP_RET_C:
            case OP_RETI:
            case OP_RST_00H:
            case OP_RST_08H:
            case OP_RST_10H:
            case OP_RST_18H:
            case OP_RST_20H:
            case OP_RST_28H:
            case OP_RST_30H:
            case OP_RST_38H:
                // TODO: Implement jumps and subroutine instructions
                break;

            // ========== Carry Flag Instructions ==========
            case OP_CCF:
            case OP_SCF:
                // TODO: Implement carry flag instructions
                break;

            // ========== Stack Manipulation Instructions ==========
            case OP_PUSH_BC:
            case OP_PUSH_DE:
            case OP_PUSH_HL:
            case OP_PUSH_AF:
            case OP_POP_BC:
            case OP_POP_DE:
            case OP_POP_HL:
            case OP_POP_AF:
            case OP_ADD_SP_s8:
                // TODO: Implement stack manipulation instructions
                break;

            // ========== Interrupt-related Instructions ==========
            case OP_DI:
            case OP_EI:
            case OP_HALT:
                // TODO: Implement interrupt-related instructions
                break;

            // ========== Miscellaneous Instructions ==========
            case OP_NOP:
            case OP_STOP:
            case OP_DAA:
                // TODO: Implement miscellaneous instructions
                break;
        }

        return mCycles;
    }
}