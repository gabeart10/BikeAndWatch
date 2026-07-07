import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Timer;

typedef GBBusRead as Method(addr as Number) as Number;
typedef GBBusWrite as Method(addr as Number, data as Number) as Void;
typedef GBClockCycle as Method() as Void;
typedef GBCPUSendIntFunc as Method(int as GameBoy.IntSrc) as Void;
typedef GBCPUOp as Method(opcode as Number) as Void;

class GameBoy {
    // General
    enum Event {
        EVENT_FRAME_DONE
    }
    enum Button {
        BUTTON_A = 0x01,
        BUTTON_B = 0x02,
        BUTTON_SELECT = 0x04,
        BUTTON_START = 0x08,
        BUTTON_RIGHT = 0x10,
        BUTTON_LEFT = 0x20,
        BUTTON_UP = 0x40,
        BUTTON_DOWN = 0x80
    }

    // CPU
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

    // PPU
    static const SCREEN_WIDTH = 160;
    static const SCREEN_HEIGHT = 144;
    const OBJ_LIM = 10;
    const OBJ_WIDTH = 8;
    const VBLANK_LINES = 10;
    const TILEMAP_START_ZERO = 0x1800;
    const TILEMAP_START_ONE = 0x1C00;
    private enum PPUMode {
        PPUMODE_HBLANK = 0,
        PPUMODE_VBLANK = 1,
        PPUMODE_OAM_SCAN = 2,
        PPUMODE_DRAW = 3
    }
    private enum StatInt {
        STAT_INT_HBLANK = 0x08,
        STAT_INT_VBLANK = 0x10,
        STAT_INT_OAM_SCAN = 0x20,
        STAT_INT_DRAW = 0x00,
        STAT_INT_LYC = 0x40
    }
    private enum PPUCycle {
        PPUCYCLE_HBLANK = 51,
        PPUCYCLE_VBLANK = 114,
        PPUCYCLE_OAM_SCAN = 20,
        PPUCYCLE_DRAW = 43
    }
    private enum LCDCBit {
        LCDCBIT_BG_WIN_EN = 0x1,
        LCDCBIT_OBJ_EN = 0x2,
        LCDCBIT_OBJ_SIZE = 0x4,
        LCDCBIT_BG_TILE_MAP = 0x8,
        LCDCBIT_BG_WIN_TILE_DATA = 0x10,
        LCDCBIT_WIN_EN = 0x20,
        LCDCBIT_WIN_TILE_MAP = 0x40,
        LCDCBIT_LCD_EN = 0x80
    }
    private enum OBJByte {
        OBJBYTE_Y_POS = 0,
        OBJBYTE_X_POS = 1,
        OBJBYTE_TILE_IDX = 2,
        OBJBYTE_ATTR = 3
    }
    private enum OBJAttrBit {
        OBJATTRBIT_PALETTE = 0x10,
        OBJATTRBIT_X_FLIP = 0x20,
        OBJATTRBIT_Y_FLIP = 0x40,
        OBJATTRBIT_PRIORITY = 0x80
    }

    // General
    private var _cart as GameCart.GameCart?;
    private var _wram as ByteArray = new[8192]b;
    private var _dummyAudio as ByteArray = new[48]b;
    private var _eventCB as Method(Event) as Void;
    private var _mainTimer as Timer.Timer = new Timer.Timer();
    private var _lastTime as Number = 0;
    private var _lastWaitTime as Number = 0;
    private var _waitTime as Number = 0;
    private var _cycleCount as Number = 0;

    // CPU
    private var _printEnable as Boolean = false;
    private var _hram as ByteArray = new[127]b;
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

    // Input
    private var _joypadDirection as Number = 0xFF;
    private var _joypadAction as Number = 0xFF;
    private var _joyp as Number = 0xCF;

    // Timer
    private const _clockFallingEdgeMaskLookup as Array<Number> = [0x00FF, 0x0003, 0x000F, 0x003F];
    private var _systemCounter as Number = 0x2AC0;
    private var _tima as Number = 0;
    private var _tma as Number = 0;
    private var _enable as Number = 0;
    private var _clockSelect as Number = 0;
    private var _clockFallingEdgeMask as Number = _clockFallingEdgeMaskLookup[0];
    private var _overflowBuffered as Boolean = false;

    // PPU
    private var _frameSkipCount as Number = 0;
    private var _bitmap as BufferedBitmap;
    private var _prevIntState as Boolean = false;
    private var _checkStat as Boolean = false;
    private var _vram as ByteArray = new[8192]b;
    private var _oam as ByteArray = new[160]b;
    private var _lcdc as Number = 0x91; // LCD Control
    private var _ly as Number = 0; // LCD Y Cord
    private var _lyc as Number = 0; // LY Compare
    private var _ppuModeTick as Number = PPUCYCLE_OAM_SCAN;
    private var _ppuMode as Number = PPUMODE_OAM_SCAN;
    private var _ppuModeStat as Number = STAT_INT_OAM_SCAN;
    private var _stat as Number = 0x80; // LCD Status
    private var _scy as Number = 0; // Background Viewport Y
    private var _scx as Number = 0; // Background Viewport X
    private var _bgp as Number = 0xFC; // Background Palette Data
    private var _obp0 as Number = 0; // OBJ0 Palette Data 
    private var _obp1 as Number = 0; // OBJ1 Palette Data 
    private var _colorMap as Array<Graphics.ColorValue> = [Graphics.COLOR_WHITE, Graphics.COLOR_LT_GRAY, Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK];
    private var _wy as Number = 0; // Window Y Pos
    private var _wx as Number = 0; // Window X Pos - 7
    private var _wYPos as Number = 0;
    private var _yCond as Boolean = false;

    // Serial
    private var _sc as Number = 0;
    private var _sb as Number = 0;
    private var _cycleCnt as Number = 0;
    private var _shiftCnt as Number = 0;

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

    function ppuFrameDone() as Void {
        _eventCB.invoke(EVENT_FRAME_DONE);

        if (PRINT_FPS) {
            var frameTimeDelta = System.getTimer() - _lastTime;
            _lastTime = System.getTimer();
            var renderFPS = 1000.0 / frameTimeDelta;
            if (PRINT_MCPS) {
                System.println(format("$1$ Render FPS | $2$ System FPS | $3$ MCycle/s | $4$% Idle", [
                    renderFPS.format("%.3f"), 
                    (renderFPS * PPU_FRAME_DIVIDER).format("%.3f"),
                    ((_cycleCount * 1000) / frameTimeDelta).format("%d"),
                    ((_waitTime * 100) / frameTimeDelta).format("%d")
                ]));
                _cycleCount = 0;
            } else {
                System.println(format("$1$ Render FPS | $2$ System FPS | $3$% Idle", [
                    renderFPS.format("%.3f"), 
                    (renderFPS * PPU_FRAME_DIVIDER).format("%.3f"),
                    ((_waitTime * 100) / frameTimeDelta).format("%d")
                ]));
            }
            _waitTime = 0;
        }
    }

    function busRead(addr as Number) as Number {
        // Make sure memory is up to date
        cycleMClock();

        if (addr < 0x8000) {
            // ROM
            return (_cart as GameCart.GameCart).busRead(addr);
        } else if (addr < 0xA000) {
            // VRAM
            return _vram[addr - 0x8000];
        } else if (addr < 0xC000 && _cart != null) {
            // External Ram
            return _cart.busRead(addr);
        } else if (addr < 0xE000) {
            // WRAM
            return _wram[addr - 0xC000];
        } else if (addr < 0xFE00) {
            // Echo WRAM
            return _wram[addr - 0xE000];
        } else if (addr < 0xFEA0) {
            // OAM
            return _oam[addr - 0xFE00];
        } else if (addr == 0xFF00) {
            // Joypad Input
            var ret = _joyp;
            if ((ret & 0x10) == 0) {
                ret &= _joypadDirection;
            }
            if ((ret & 0x20) == 0) {
                ret &= _joypadAction;
            }
            return ret;
        } else if (addr < 0xFF03) {
            //Serial Transfer
            if (PRINT_SERIAL && addr == 0xFF01) {
                return _sb & 0xFF;
            } else if (PRINT_SERIAL && addr == 0xFF02) {
                return _sc;
            } else {
                return 0xFF;
            }
        } else if (addr == 0xFF04) {
            // DIV
            return _systemCounter >> 6;
        } else if (addr == 0xFF05) {
            // TIMA
            return _tima;
        } else if (addr == 0xFF06) {
            // TMA
            return _tma;
        } else if (addr == 0xFF07) {
            // TAC
            return 0xF8 | (_enable << 2) | _clockSelect;
        } else if (addr == 0xFF0F) {
            // Interrupt Flag
            return _if | 0xE0;
        } else if (addr < 0xFF40) {
            // Audio (dummied out by acting as normal ram)
            return _dummyAudio[addr - 0xFF10];
        } else if (addr == 0xFF40) {
            // LCD Control
            return _lcdc;
        } else if (addr == 0xFF41) {
            // LCD Status
            return _stat | (((_lyc == _ly) ? 0x1 : 0x0) << 2) | _ppuMode;
        } else if (addr == 0xFF42) {
            // Background Viewport Y
            return _scy;
        } else if (addr == 0xFF43) {
            // Background Viewport X
            return _scx;
        } else if (addr == 0xFF44) {
            // LCD Y Cord
            return _ly;
        } else if (addr == 0xFF45) {
            // LY Compare
            return _lyc;
        } else if (addr == 0xFF47) {
            // BG Palette Data
            return _bgp;
        } else if (addr == 0xFF48) {
            // OBJ0 Palette Data
            return _obp0;
        } else if (addr == 0xFF49) {
            // OBJ1 Palette Data
            return _obp1;
        } else if (addr == 0xFF4A) {
            // Window Y Pos
            return _wy;
        } else if (addr == 0xFF4B) {
            // Window X Pos
            return _wx + 7;
        } else if (addr == 0xFFFF) {
            // Interrupt Enable
            return _ie;
        } else if (addr >= 0xFF80) {
            // HRAM
            return _hram[addr - 0xFF80];
        }
        return 0xFF;
    }

    function busWrite(addr as Number, data as Number) as Void {
        // Make sure memory is up to date
        cycleMClock();

        if (addr < 0x8000) {
            // ROM
            (_cart as GameCart.GameCart).busWrite(addr, data);
        } else if (addr < 0xA000) {
            // VRAM
            _vram[addr - 0x8000] = data;
        } else if (addr < 0xC000 && _cart != null) {
            // External Ram
            _cart.busWrite(addr, data);
        } else if (addr < 0xE000) {
            // WRAM
            _wram[addr - 0xC000] = data;
        } else if (addr < 0xFE00) {
            // Echo WRAM
            _wram[addr - 0xE000] = data;
        } else if (addr < 0xFEA0) {
            // OAM
            _oam[addr - 0xFE00] = data;
        } else if (addr == 0xFF00) {
            // Joypad Input
            _joyp = (data & 0x30) | 0xCF;
        } else if (PRINT_SERIAL && addr == 0xFF01) {
            _sb = data;
        } else if (PRINT_SERIAL && addr == 0xFF02) {
            _sc = data;
        } else if (addr == 0xFF04) {
            // DIV
            _systemCounter = 0;
        } else if (addr == 0xFF05) {
            // TIMA
            _tima = data;
            _overflowBuffered = false;
        } else if (addr == 0xFF06) {
            // TMA
            _tma = data;
        } else if (addr == 0xFF07) {
            // TAC
            _clockSelect = data & 0x3;
            _clockFallingEdgeMask = _clockFallingEdgeMaskLookup[_clockSelect];
            _enable = (data >> 2) & 0x1;
        } else if (addr < 0xFF0F) {
            return;
        } else if (addr == 0xFF0F) {
            // Interrupt Flag
            _if = data;
        } else if (addr < 0xFF40) {
            // Audio (dummied out by acting as normal ram)
            _dummyAudio[addr - 0xFF10] = data;
        } else if (addr == 0xFF40) {
            // LCD Control
            if ((data & LCDCBIT_LCD_EN) == 0) {
                // Reset PPU if disabled
                _ly = 0;
                _wYPos = 0;
                _yCond = false;
                _frameSkipCount = 0;
                _ppuMode = PPUMODE_OAM_SCAN;
                _ppuModeStat = STAT_INT_OAM_SCAN;
                _ppuModeTick = PPUCYCLE_OAM_SCAN;
            }
            _lcdc = data;
        } else if (addr == 0xFF41) {
            // LCD Status
            _stat = data & 0x78;
            _checkStat = true;
        } else if (addr == 0xFF42) {
            // Background Viewport Y
            _scy = data;
        } else if (addr == 0xFF43) {
            // Background Viewport X
            _scx = data;
        } else if (addr == 0xFF45) {
            // LY Compare
            _lyc = data;
            _checkStat = true;
        } else if (addr == 0xFF47) {
            // BG Palette Data
            _bgp = data;
        } else if (addr == 0xFF48) {
            // OBJ0 Palette Data
            _obp0 = data;
        } else if (addr == 0xFF49) {
            // OBJ1 Palette Data
            _obp1 = data;
        } else if (addr == 0xFF4A) {
            // Window Y Pos
            _wy = data;
        } else if (addr == 0xFF4B) {
            // Window X Pos
            _wx = data - 7;
        } else if (addr == 0xFF46) {
            // OAM DMA
            var src = data << 8;
            for (var dest = 0x0; dest < 0xA0; dest++) {
                if (addr < 0x8000) {
                    // ROM
                    _oam[dest] = (_cart as GameCart.GameCart).busRead(src);
                } else if (addr < 0xA000) {
                    // VRAM
                    _oam[dest] = _vram[addr - 0x8000];
                } else if (addr < 0xC000 && _cart != null) {
                    // External Ram
                    _oam[dest] = _cart.busRead(addr);
                } else if (addr < 0xE000) {
                    // WRAM
                    _oam[dest] = _wram[addr - 0xC000];
                }
                src++;
            }
        } else if (addr == 0xFFFF) {
            // Interrupt Enable
            _ie = data;
        } else if (addr >= 0xFF80) {
            // HRAM
            _hram[addr - 0xFF80] = data;
        }
    }

    function emuCycle() as Void {
        _waitTime += System.getTimer() - _lastWaitTime;
        for (var i = 0; i < STEPS_PER_CYCLE; i++) {
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
                        cycleMClock();
                        cycleMClock();
                        cycleMClock();
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
                            cycleMClock();
                        }
                        break;
                    }
                }
            }

            if (PRINT_TRACE) {
                if (_printEnable) {
                    System.println(
                        "0x" + (_pc - 1).format("%04X")
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

            // Don't process _imeNext if Op EI just ran
            if (_imeNext && opcode != 0xFB) {
                _imeNext = false;
                _ime = true;
            }
        }
        _lastWaitTime = System.getTimer();
    }

    private function drawLine() as Void {
        var bmDc = _bitmap.getDc();
        var selOBJs = (new[0]) as Array<Number>;
        var objHeight = (_lcdc & LCDCBIT_OBJ_SIZE) ? 16 : 8; 

        // Get OBJs on line
        if (_lcdc & LCDCBIT_OBJ_EN) {
            for (var oamIdx = 0; oamIdx < 160; oamIdx += 4) {
                var objYScreen = _oam[oamIdx + OBJBYTE_Y_POS] - 16;
                if (objYScreen <= _ly && _ly < (objYScreen + objHeight)) {
                    // Add X Pos to 2nd Byte to allow for correct priority sorting
                    selOBJs.add((_oam[oamIdx + OBJBYTE_X_POS] << 8) | oamIdx);
                    if (selOBJs.size() == OBJ_LIM) {
                        // Reached OBJ Limit per Line
                        break;
                    }
                }
            }
            selOBJs.sort(null);
        }

        var objsFound = selOBJs.size();
        var objStartIdx = 0;
        var tileDataAddrMode = _lcdc & LCDCBIT_BG_WIN_TILE_DATA;

        var bgEn = _lcdc & LCDCBIT_BG_WIN_EN;
        var bgYPos = (_scy + _ly) % 256;
        var bgTileY = bgYPos % 8;
        var bgTileIdxStart = (_lcdc & LCDCBIT_BG_TILE_MAP) ? TILEMAP_START_ONE : TILEMAP_START_ZERO;
        bgTileIdxStart += (bgYPos / 8) * 32;

        var wEn = (bgEn != 0) && ((_lcdc & LCDCBIT_WIN_EN) != 0);
        var wTileY = _wYPos % 8;
        var wTileIdxStart = (_lcdc & LCDCBIT_WIN_TILE_MAP) ? TILEMAP_START_ONE : TILEMAP_START_ZERO;
        wTileIdxStart += (_wYPos / 8) * 32;

        for (var lineX = 0; lineX < SCREEN_WIDTH; lineX++) {
            // Find window or background tile and tile cords
            var baseColorIdx = 0;
            var baseColor = 0;
            var baseTileIdx = null;
            var baseTileX = null;
            var baseTileY = null;
            if (wEn && _yCond && lineX >= _wx) {
                var wX = lineX - _wx;
                baseTileIdx = _vram[wTileIdxStart + (wX / 8)];
                baseTileX = 7 - (wX % 8);
                baseTileY = wTileY;
            } else if (bgEn) {
                var bgX = (lineX + _scx) % 256;
                baseTileIdx = _vram[bgTileIdxStart + (bgX / 8)];
                baseTileX = 7 - (bgX % 8);
                baseTileY = bgTileY;
            }

            // Find window or background color
            if (baseTileIdx != null) {
                var tileDataIdx = (baseTileY as Number) * 2;
                if (tileDataAddrMode) {
                    tileDataIdx += baseTileIdx * 16;
                } else {
                    tileDataIdx += 0x1000 + ((baseTileIdx << 24) >> 24) * 16;
                }
                baseColorIdx = ((_vram[tileDataIdx + 1] >> (baseTileX as Number)) & 0x1) << 1;
                baseColorIdx |= (_vram[tileDataIdx] >> (baseTileX as Number)) & 0x1;
                baseColor = (_bgp >> (baseColorIdx * 2)) & 0x3;
            }

            // Check for object overwriting background/window color
            for (var objIdx = objStartIdx; objIdx < objsFound; objIdx++) {
                // Fetch X pos from 2nd Byte
                var objX = (selOBJs[objIdx] >> 8) - 8;
                if (objX <= lineX) {
                    if (lineX < (objX + OBJ_WIDTH)) {
                        // Found possible OBJ
                        var objOAMIdx = selOBJs[objIdx] & 0xFF;
                        var objAttr = _oam[objOAMIdx + OBJBYTE_ATTR];
                        var objTileIdx = _oam[objOAMIdx + OBJBYTE_TILE_IDX];
                        var objTileX;
                        var objTileY;

                        if (objHeight == 16) {
                            // Enforce Ignoring LSB for 8x16 Objs
                            objTileIdx &= 0xFE;
                        }
                        objTileIdx *= 16;

                        if (objAttr & OBJATTRBIT_X_FLIP) {
                            objTileX = lineX - objX;
                        } else {
                            objTileX = 7 - (lineX - objX);
                        }

                        objTileY = _ly - (_oam[objOAMIdx + OBJBYTE_Y_POS] - 16);
                        if (objAttr & OBJATTRBIT_Y_FLIP) {
                            objTileY = objHeight - 1 - objTileY;
                        }

                        objTileIdx += objTileY * 2;
                        var objColorIdx = ((_vram[objTileIdx + 1] >> objTileX) & 0x1) << 1;
                        objColorIdx |= (_vram[objTileIdx] >> objTileX) & 0x1;
                        if (objColorIdx != 0) {
                            // Found OBJ to use for this pixel
                            if (baseColor == 0 || (objAttr & OBJATTRBIT_PRIORITY) == 0) {
                                var objPalette = (objAttr & OBJATTRBIT_PALETTE) ? _obp1 : _obp0;
                                baseColor = (objPalette >> (objColorIdx * 2)) & 0x3;
                            }
                            // Always break on first non-transparent obj color
                            break;
                        }
                    } else {
                        // If we reach here we are past the obj, update start 
                        // idx so we don't iterate over this obj again
                        objStartIdx = objIdx;
                    }
                }
            }

            // Draw pixel on bitmap
            bmDc.setColor(_colorMap[baseColor], Graphics.COLOR_PINK);
            bmDc.drawPoint(lineX, _ly);
        }

        // If we drew any of the window on this line increase wYPos
        if (wEn && _yCond && _wx < SCREEN_WIDTH) {
            _wYPos++;
        }
    }

    function cycleMClock() as Void {
        // Timer
        // Using CGB configuration
        // TODO check if emulating DMG or CGB config is faster 
        _systemCounter = (_systemCounter + 1) & 0x3FFF;

        if (_overflowBuffered) {
            _tima = _tma;
            _if |= (0x1 << INT_TIMER);
            _overflowBuffered = false;
        } else if ((_enable != 0) && ((_systemCounter & _clockFallingEdgeMask) == 0)) {
            var newTima = _tima + 1;
            if (newTima > 0xFF) {
                _tima = 0;
                _overflowBuffered = true;
            } else {
                _tima = newTima;
            }
        }

        // PPU
        if (_lcdc & 0x80) {
            var ppuTick = _ppuModeTick - 1;
            if (ppuTick) {
                _ppuModeTick = ppuTick;
            } else {
                var mode = _ppuMode;
                if (mode == PPUMODE_OAM_SCAN) {
                    _ppuMode = PPUMODE_DRAW;
                    _ppuModeStat = STAT_INT_DRAW;
                    _ppuModeTick = PPUCYCLE_DRAW;
                } else if (mode == PPUMODE_DRAW) {
                    if (_ly == _wy) {
                        _yCond = true;
                    }
                    if (_frameSkipCount == 0) {
                        drawLine();
                    }
                    _ppuMode = PPUMODE_HBLANK;
                    _ppuModeStat = STAT_INT_HBLANK; 
                    _ppuModeTick = PPUCYCLE_HBLANK;
                } else if (mode == PPUMODE_HBLANK) {
                    _ly++;
                    if (_ly == SCREEN_HEIGHT) {
                        if (_frameSkipCount == 0) {
                            ppuFrameDone();
                        }
                        _if |= (0x1 << INT_VBLANK);
                        _ppuMode = PPUMODE_VBLANK;
                        _ppuModeStat = STAT_INT_VBLANK;
                        _ppuModeTick = PPUCYCLE_VBLANK;
                    } else {
                        _ppuMode = PPUMODE_OAM_SCAN;
                        _ppuModeStat = STAT_INT_OAM_SCAN;
                        _ppuModeTick = PPUCYCLE_OAM_SCAN;
                    }
                } else if (mode == PPUMODE_VBLANK) {
                    _ly++;
                    if (_ly == (SCREEN_HEIGHT + VBLANK_LINES)) {
                        _ly = 0;
                        _wYPos = 0;
                        _yCond = false;
                        _frameSkipCount = (_frameSkipCount + 1) % PPU_FRAME_DIVIDER;
                        _ppuMode = PPUMODE_OAM_SCAN;
                        _ppuModeStat = STAT_INT_OAM_SCAN;
                        _ppuModeTick = PPUCYCLE_OAM_SCAN;
                    } else {
                        _ppuModeTick = PPUCYCLE_VBLANK;
                    }
                }
                _checkStat = true;
            }

            // Check for STAT interrupt
            if (_checkStat) {
                _checkStat = false;
                var triggered = ((((_lyc == _ly) ? STAT_INT_LYC : 0x00) | _ppuModeStat) & _stat) != 0;
                if (triggered && !_prevIntState) {
                    // Only interrupt on rising edge
                    _if |= (0x1 << INT_LCD);
                }
                _prevIntState = triggered;
            }
        }

        // Serial
        if (PRINT_SERIAL) {
            _cycleCnt++;
            if (_cycleCnt == 128) {
                _cycleCnt = 0;
                if ((_sc & 0x81) == 0x81) {
                    _sb <<= 1;
                    _shiftCnt++;
                    if (_shiftCnt >= 8) {
                        _shiftCnt = 0;
                        _sc &= 0x7F;
                        _if |= (0x1 << INT_SERIAL);
                        System.print((_sb >> 8).toChar());
                    }
                }
            }
        }
        if (PRINT_FPS && PRINT_MCPS) {
            _cycleCount++;
        }
    }

    function initialize(eventCB as Method(Event) as Void) {
        _eventCB = eventCB;
        var bitmap = Graphics.createBufferedBitmap({
            :width => SCREEN_WIDTH,
            :height => SCREEN_HEIGHT
        }).get();

        if (bitmap != null) {
            _bitmap = bitmap as Graphics.BufferedBitmap;
        } else {
            System.println("Failed to create PPU bitmap");
            throw new Lang.Exception();
        }
    }

    function insertCart(cart as GameCart.GameCart?) as Void {
        _cart = cart;
    }

    function start() as Void {
        _lastTime = System.getTimer();
        _mainTimer.start(method(:emuCycle), EMU_CYCLE_MS, true);
    }

    function stop() as Void {
        _mainTimer.stop();
    }

    function getFrame() as BufferedBitmap {
        return _bitmap;
    } 

    function pressButton(bttn as Button) as Void {
        var prev = busRead(0xFF00);
        if (bttn > BUTTON_START) {
            bttn >>= 4;
            _joypadDirection &= ~bttn;
            if (prev != busRead(0xFF00)) {
                _if |= (0x1 << INT_JOYPAD);
            }
        } else {
            _joypadAction &= ~bttn;
        }
        if (prev != busRead(0xFF00)) {
            _if |= (0x1 << INT_JOYPAD);
        }
    }

    function releaseButton(bttn as Button) as Void {
        if (bttn > BUTTON_START) {
            bttn >>= 4;
            _joypadDirection |= bttn;
        } else {
            _joypadAction |= bttn;
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
        cycleMClock();
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
        cycleMClock();
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
        cycleMClock();
    }

    function op_dec_rr(opcode as Number) as Void {
        var reg = ((opcode >> 4) & 0x3) as RegistersEnum;
        set16BitReg(reg, get16BitReg(reg) - 1);
        cycleMClock();
    }

    function op_add_HL_rr(opcode as Number) as Void {
        var HL = get16BitReg(REG_HL);
        var reg = get16BitReg(((opcode >> 4) & 0x3) as RegistersEnum);
        var result = HL + reg;
        set16BitReg(REG_HL, result);
        _NFlag = 0;
        _HFlag = (HL ^ reg ^ result) & 0x1000;
        _CFlag = result & 0x10000;
        cycleMClock();
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
        cycleMClock();
    }

    function op_jp_hl(opcode as Number) as Void {
        _pc = get16BitReg(REG_HL);
    }

    function op_jp_nz(opcode as Number) as Void {
        if (_nZFlag) {
            _pc = (busRead(_pc + 1) << 8) | busRead(_pc);
        } else {
            _pc += 2;
            cycleMClock();
        }
        cycleMClock();
    }

    function op_jp_z(opcode as Number) as Void {
        if (_nZFlag == 0) {
            _pc = (busRead(_pc + 1) << 8) | busRead(_pc);
        } else {
            _pc += 2;
            cycleMClock();
        }
        cycleMClock();
    }

    function op_jp_nc(opcode as Number) as Void {
        if (_CFlag == 0) {
            _pc = (busRead(_pc + 1) << 8) | busRead(_pc);
        } else {
            _pc += 2;
            cycleMClock();
        }
        cycleMClock();
    }

    function op_jp_c(opcode as Number) as Void {
        if (_CFlag) {
            _pc = (busRead(_pc + 1) << 8) | busRead(_pc);
        } else {
            _pc += 2;
            cycleMClock();
        }
        cycleMClock();
    }

    function op_jr_s8(opcode as Number) as Void {
        _pc = (_pc + 1 + ((busRead(_pc) << 24) >> 24)) & 0xFFFF;
        cycleMClock();
    }

    function op_jr_nz(opcode as Number) as Void {
        if (_nZFlag) {
            _pc = (_pc + 1 + ((busRead(_pc) << 24) >> 24)) & 0xFFFF;
        } else {
            _pc++;
        }
        cycleMClock();
    }

    function op_jr_z(opcode as Number) as Void {
        if (_nZFlag == 0) {
            _pc = (_pc + 1 + ((busRead(_pc) << 24) >> 24)) & 0xFFFF;
        } else {
            _pc++;
        }
        cycleMClock();
    }

    function op_jr_nc(opcode as Number) as Void {
        if (_CFlag == 0) {
            _pc = (_pc + 1 + ((busRead(_pc) << 24) >> 24)) & 0xFFFF;
        } else {
            _pc++;
        }
        cycleMClock();
    }

    function op_jr_c(opcode as Number) as Void {
        if (_CFlag) {
            _pc = (_pc + 1 + ((busRead(_pc) << 24) >> 24)) & 0xFFFF;
        } else {
            _pc++;
        }
        cycleMClock();
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
        cycleMClock();
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
            cycleMClock();
        }
        cycleMClock();
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
            cycleMClock();
        }
        cycleMClock();
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
            cycleMClock();
        }
        cycleMClock();
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
            cycleMClock();
        }
        cycleMClock();
    }


    function op_ret_and_reti(opcode as Number) as Void {
        if (opcode & 0x10) {
            _ime = true;
        }
        _pc = busRead(_sp);
        _sp += 1;
        _pc |= busRead(_sp) << 8; 
        _sp += 1;
        cycleMClock();
    }

    function op_ret_nz(opcode as Number) as Void {
        if (_nZFlag) {
            _pc = busRead(_sp);
            _sp += 1;
            _pc |= busRead(_sp) << 8; 
            _sp += 1;
            cycleMClock();
        }
        cycleMClock();
    }

    function op_ret_z(opcode as Number) as Void {
        if (_nZFlag == 0) {
            _pc = busRead(_sp);
            _sp += 1;
            _pc |= busRead(_sp) << 8; 
            _sp += 1;
            cycleMClock();
        }
        cycleMClock();
    }

    function op_ret_nc(opcode as Number) as Void {
        if (_CFlag == 0) {
            _pc = busRead(_sp);
            _sp += 1;
            _pc |= busRead(_sp) << 8; 
            _sp += 1;
            cycleMClock();
        }
        cycleMClock();
    }

    function op_ret_c(opcode as Number) as Void {
        if (_CFlag) {
            _pc = busRead(_sp);
            _sp += 1;
            _pc |= busRead(_sp) << 8; 
            _sp += 1;
            cycleMClock();
        }
        cycleMClock();
    }

    function op_rst(opcode as Number) as Void {
        _sp -= 1;
        busWrite(_sp, _pc >> 8);
        _sp -= 1;
        busWrite(_sp, _pc & 0xFF);
        _pc = opcode & 0x38;
        cycleMClock();
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
        cycleMClock();
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
        cycleMClock();
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
        cycleMClock();
        cycleMClock();
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