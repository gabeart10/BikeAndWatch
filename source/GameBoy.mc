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
    private var _regA as Number = 0x01;
    private var _regB as Number = 0x00;
    private var _regC as Number = 0x13;
    private var _regD as Number = 0x00;
    private var _regE as Number = 0xD8;
    private var _regH as Number = 0x01;
    private var _regL as Number = 0x4D;

    // Input
    private var _joypadDirection as Number = 0xFF;
    private var _joypadAction as Number = 0xFF;
    private var _joyp as Number = 0xCF;

    // Timer
    private const _clockShiftLookup as Array<Number> = [8, 2, 4, 6];
    private var _systemCounter as Number = 0x2AC0;
    private var _tima as Number = 0;
    private var _tma as Number = 0;
    private var _enable as Number = 0;
    private var _clockSelect as Number = 0;
    private var _clockShift as Number = _clockShiftLookup[0];

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

    function ppuFrameDone() as Void {
        _eventCB.invoke(EVENT_FRAME_DONE);

        if (PRINT_FPS) {
            var frameTimeDelta = System.getTimer() - _lastTime;
            _lastTime = System.getTimer();
            var renderFPS = 1000.0 / frameTimeDelta;
            System.println(format("$1$ Render FPS | $2$ System FPS | $3$% Idle", [
                renderFPS.format("%.3f"), 
                (renderFPS * PPU_FRAME_DIVIDER).format("%.3f"),
                ((_waitTime * 100) / frameTimeDelta).format("%d")
            ]));
            _waitTime = 0;
        }
    }

    function busRead(addr as Number) as Number {
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
            return 0xFF;
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
        } else if (addr == 0xFF04) {
            // DIV
            _systemCounter = 0;
        } else if (addr == 0xFF05) {
            // TIMA
            _tima = data;
        } else if (addr == 0xFF06) {
            // TMA
            _tma = data;
        } else if (addr == 0xFF07) {
            // TAC
            _clockSelect = data & 0x3;
            _clockShift = _clockShiftLookup[_clockSelect];
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

    function cycleMClock(cycles as Number) as Void {
        // Timer
        var oldSys = _systemCounter;
        var newSys = oldSys + cycles;
        _systemCounter = newSys & 0x3FFF;

        if (_enable) {
            var ticks = (newSys >> _clockShift) - (oldSys >> _clockShift);
            if (ticks) {
                var newTima = _tima + ticks;
                if (newTima > 0xFF) {
                    _tima = (_tma + newTima) & 0xFF;
                    _if |= (0x1 << INT_TIMER);
                } else {
                    _tima = newTima;
                }
            }
        }

        // PPU
        if (_lcdc & 0x80) {
            var ppuTick = _ppuModeTick - cycles;
            if (ppuTick > 0) {
                _ppuModeTick = ppuTick;
            } else {
                while (ppuTick <= 0) {
                    var mode = _ppuMode;
                    if (mode == PPUMODE_OAM_SCAN) {
                        _ppuMode = PPUMODE_DRAW;
                        _ppuModeStat = STAT_INT_DRAW;
                        ppuTick += PPUCYCLE_DRAW;
                    } else if (mode == PPUMODE_DRAW) {
                        if (_ly == _wy) {
                            _yCond = true;
                        }
                        if (_frameSkipCount == 0) {
                            drawLine();
                        }
                        _ppuMode = PPUMODE_HBLANK;
                        _ppuModeStat = STAT_INT_HBLANK; 
                        ppuTick += PPUCYCLE_HBLANK;
                    } else if (mode == PPUMODE_HBLANK) {
                        _ly++;
                        if (_ly == SCREEN_HEIGHT) {
                            if (_frameSkipCount == 0) {
                                ppuFrameDone();
                            }
                            _if |= (0x1 << INT_VBLANK);
                            _ppuMode = PPUMODE_VBLANK;
                            _ppuModeStat = STAT_INT_VBLANK;
                            ppuTick += PPUCYCLE_VBLANK;
                        } else {
                            _ppuMode = PPUMODE_OAM_SCAN;
                            _ppuModeStat = STAT_INT_OAM_SCAN;
                            ppuTick += PPUCYCLE_OAM_SCAN;
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
                            ppuTick += PPUCYCLE_OAM_SCAN;
                        } else {
                            ppuTick += PPUCYCLE_VBLANK;
                        }
                    }
                }
                _checkStat = true;
                _ppuModeTick = ppuTick;
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

    function emuCycle() as Void {
        _waitTime += System.getTimer() - _lastWaitTime;
        var state = _state;
        var pc = _pc;
        var sp = _sp;
        var nZFlag = _nZFlag;
        var NFlag = _NFlag;
        var HFlag = _HFlag;
        var CFlag = _CFlag;
        var ime = _ime;
        var imeNext = _imeNext;
        var ie = _ie;
        var regA = _regA;
        var regB = _regB;
        var regC = _regC;
        var regD = _regD;
        var regE = _regE;
        var regH = _regH;
        var regL = _regL;
        for (var i = 0; i < STEPS_PER_CYCLE; i++) {
            var opcode = 0x00;

            // Check for Interrupt
            if (ime && (_if & ie & 0x1F) != 0) {
                var readyInts = _if & ie;
                ime = false;
                for (var bit = 0; bit < INT_END; bit++) {
                    if (readyInts & 0x1) {
                        // Clear Interrupt Flag
                        _if &= ~(0x1 << bit);
                        // Push PC to Stack
                        sp--;
                        busWrite(sp, pc >> 8);
                        sp--;
                        busWrite(sp, pc & 0xFF);
                        // Set PC to ISR
                        pc = 0x40 + (bit * 0x8);
                        // Make sure state is correct and add delay
                        state = CPU_STATE_RUNNING;
                        cycleMClock(5);
                        break;
                    }
                    readyInts >>= 1;
                } 
            } else {
                switch (state) {
                    case CPU_STATE_RUNNING: {
                        opcode = busRead(pc);
                        pc++;
                        break;
                    }

                    case CPU_STATE_START_HALT: 
                    case CPU_STATE_HALTED: {
                        if (_if & ie & 0x1F) {
                            opcode = busRead(pc);
                            // Simulate HALT Bug
                            if (state != CPU_STATE_START_HALT) {
                                pc++;
                            }
                            state = CPU_STATE_RUNNING;
                        } else {
                            state = CPU_STATE_HALTED;
                            // Look at better methods of handling halt
                            cycleMClock(4);
                        }
                        break;
                    }
                }
            }

            if (PRINT_TRACE) {
                if (_printEnable) {
                    System.println(
                        "0x" + (pc - 1).format("%04X")
                        + " " + _opStrings[opcode]
                        + " | SP:0x" + sp.format("%04X")
                        + " A:0x" + regA.format("%02X")
                        + " B:0x" + regB.format("%02X")
                        + " C:0x" + regC.format("%02X")
                        + " D:0x" + regD.format("%02X")
                        + " E:0x" + regE.format("%02X")
                        + " H:0x" + regH.format("%02X")
                        + " L:0x" + regL.format("%02X")
                        + " Z:" + (nZFlag == 0 ? "1" : "0")
                        + " N:" + (NFlag != 0 ? "1" : "0")
                        + " H:" + (HFlag != 0 ? "1" : "0")
                        + " C:" + (CFlag != 0 ? "1" : "0")
                    );
                }
            }

            // TODO: I really just need to use a precompiler to split this file up at this point
            if (opcode <= 0x7F) {
                if (opcode <= 0x3F) {
                    if (opcode <= 0x1F) {
                        if (opcode <= 0x0F) {
                            if (opcode <= 0x07) {
                                if (opcode <= 0x03) {
                                    if (opcode <= 0x01) {
                                        if (opcode <= 0x00) {
                                            // 0x00: NOP
                                            cycleMClock(1);
                                        } else {
                                            // 0x01: LD BC,d16
                                            regC = busRead(pc);
                                            pc++;
                                            regB = busRead(pc);
                                            pc++;
                                            cycleMClock(3);
                                        }
                                    } else {
                                        if (opcode <= 0x02) {
                                            // 0x02: LD (BC),A
                                            busWrite((regB << 8) | regC, regA);
                                            cycleMClock(2);
                                        } else {
                                            // 0x03: INC BC
                                            regC = (regC + 1) & 0xFF;
                                            if (regC == 0) {
                                                regB = (regB + 1) & 0xFF;
                                            }
                                            cycleMClock(2);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x05) {
                                        if (opcode <= 0x04) {
                                            // 0x04: INC B
                                            var result = regB + 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regB ^ result) & 0x10;
                                            regB = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x05: DEC B
                                            var result = regB - 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regB ^ result) & 0x10;
                                            regB = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x06) {
                                            // 0x06: LD B,d8
                                            regB = busRead(pc);
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0x07: RLCA
                                            CFlag = (regA >> 7) & 0x1;
                                            regA = ((regA << 1) | CFlag) & 0xFF;
                                            nZFlag = 1;
                                            NFlag = 0;
                                            HFlag = 0;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0x0B) {
                                    if (opcode <= 0x09) {
                                        if (opcode <= 0x08) {
                                            // 0x08: LD (a16),SP
                                            var addr = busRead(pc);
                                            pc++;
                                            addr |= busRead(pc) << 8;
                                            pc++;
                                            busWrite(addr, sp & 0xFF);
                                            busWrite(addr + 1, (sp >> 8) & 0xFF);
                                            cycleMClock(5);
                                        } else {
                                            // 0x09: ADD HL,BC
                                            var HL = (regH << 8) | regL;
                                            var reg = (regB << 8) | regC;
                                            var result = HL + reg;
                                            regH = (result >> 8) & 0xFF;
                                            regL = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (HL ^ reg ^ result) & 0x1000;
                                            CFlag = result & 0x10000;
                                            cycleMClock(2);
                                        }
                                    } else {
                                        if (opcode <= 0x0A) {
                                            // 0x0A: LD A,(BC)
                                            regA = busRead((regB << 8) | regC);
                                            cycleMClock(2);
                                        } else {
                                            // 0x0B: DEC BC
                                            var result = ((regB << 8) | regC) - 1;
                                            regB = (result >> 8) & 0xFF;
                                            regC = result & 0xFF;
                                            cycleMClock(2);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x0D) {
                                        if (opcode <= 0x0C) {
                                            // 0x0C: INC C
                                            var result = regC + 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regC ^ result) & 0x10;
                                            regC = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x0D: DEC C
                                            var result = regC - 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regC ^ result) & 0x10;
                                            regC = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x0E) {
                                            // 0x0E: LD C,d8
                                            regC = busRead(pc);
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0x0F: RRCA
                                            CFlag = regA & 0x1;
                                            regA = (regA >> 1) | (CFlag << 7);
                                            nZFlag = 1;
                                            NFlag = 0;
                                            HFlag = 0;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            }
                        } else {
                            if (opcode <= 0x17) {
                                if (opcode <= 0x13) {
                                    if (opcode <= 0x11) {
                                        if (opcode <= 0x10) {
                                            // 0x10: STOP
                                            System.println("Opcode not implemented: 0x" + opcode.format("%02X"));
                                            throw new Lang.Exception();
                                        } else {
                                            // 0x11: LD DE,d16
                                            regE = busRead(pc);
                                            pc++;
                                            regD = busRead(pc);
                                            pc++;
                                            cycleMClock(3);
                                        }
                                    } else {
                                        if (opcode <= 0x12) {
                                            // 0x12: LD (DE),A
                                            busWrite((regD << 8) | regE, regA);
                                            cycleMClock(2);
                                        } else {
                                            // 0x13: INC DE
                                            var result = ((regD << 8) | regE) + 1;
                                            regD = (result >> 8) & 0xFF;
                                            regE = result & 0xFF;
                                            cycleMClock(2);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x15) {
                                        if (opcode <= 0x14) {
                                            // 0x14: INC D
                                            var result = regD + 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regD ^ result) & 0x10;
                                            regD = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x15: DEC D
                                            var result = regD - 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regD ^ result) & 0x10;
                                            regD = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x16) {
                                            // 0x16: LD D,d8
                                            regD = busRead(pc);
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0x17: RLA
                                            var oldCFlag = (CFlag) ? 1 : 0;
                                            CFlag = (regA >> 7) & 0x1;
                                            regA = ((regA << 1) | oldCFlag) & 0xFF;
                                            nZFlag = 1;
                                            NFlag = 0;
                                            HFlag = 0;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0x1B) {
                                    if (opcode <= 0x19) {
                                        if (opcode <= 0x18) {
                                            // 0x18: JR r8
                                            pc = (pc + 1 + ((busRead(pc) << 24) >> 24)) & 0xFFFF;
                                            cycleMClock(3);
                                        } else {
                                            // 0x19: ADD HL,DE
                                            var HL = (regH << 8) | regL;
                                            var reg = (regD << 8) | regE;
                                            var result = HL + reg;
                                            regH = (result >> 8) & 0xFF;
                                            regL = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (HL ^ reg ^ result) & 0x1000;
                                            CFlag = result & 0x10000;
                                            cycleMClock(2);
                                        }
                                    } else {
                                        if (opcode <= 0x1A) {
                                            // 0x1A: LD A,(DE)
                                            regA = busRead((regD << 8) | regE);
                                            cycleMClock(2);
                                        } else {
                                            // 0x1B: DEC DE
                                            var result = ((regD << 8) | regE) - 1;
                                            regD = (result >> 8) & 0xFF;
                                            regE = result & 0xFF;
                                            cycleMClock(2);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x1D) {
                                        if (opcode <= 0x1C) {
                                            // 0x1C: INC E
                                            var result = regE + 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regE ^ result) & 0x10;
                                            regE = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x1D: DEC E
                                            var result = regE - 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regE ^ result) & 0x10;
                                            regE = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x1E) {
                                            // 0x1E: LD E,d8
                                            regE = busRead(pc);
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0x1F: RRA
                                            var oldCFlag = (CFlag) ? 1 : 0;
                                            CFlag = regA & 0x1;
                                            regA = (regA >> 1) | (oldCFlag << 7);
                                            nZFlag = 1;
                                            NFlag = 0;
                                            HFlag = 0;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        if (opcode <= 0x2F) {
                            if (opcode <= 0x27) {
                                if (opcode <= 0x23) {
                                    if (opcode <= 0x21) {
                                        if (opcode <= 0x20) {
                                            // 0x20: JR NZ,r8
                                            if (nZFlag) {
                                                pc = (pc + 1 + ((busRead(pc) << 24) >> 24)) & 0xFFFF;
                                                cycleMClock(3);
                                            } else {
                                                pc++;
                                                cycleMClock(2);
                                            }
                                        } else {
                                            // 0x21: LD HL,d16
                                            regL = busRead(pc);
                                            pc++;
                                            regH = busRead(pc);
                                            pc++;
                                            cycleMClock(3);
                                        }
                                    } else {
                                        if (opcode <= 0x22) {
                                            // 0x22: LDI (HL),A
                                            var hl = (regH << 8) | regL;
                                            busWrite(hl, regA);
                                            hl++;
                                            regH = (hl >> 8) & 0xFF;
                                            regL = hl & 0xFF;
                                            cycleMClock(2);
                                        } else {
                                            // 0x23: INC HL
                                            var result = ((regH << 8) | regL) + 1;
                                            regH = (result >> 8) & 0xFF;
                                            regL = result & 0xFF;
                                            cycleMClock(2);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x25) {
                                        if (opcode <= 0x24) {
                                            // 0x24: INC H
                                            var result = regH + 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regH ^ result) & 0x10;
                                            regH = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x25: DEC H
                                            var result = regH - 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regH ^ result) & 0x10;
                                            regH = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x26) {
                                            // 0x26: LD H,d8
                                            regH = busRead(pc);
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0x27: DAA
                                            var adj = 0;
                                            if ((HFlag != 0) || ((NFlag == 0) && ((regA & 0xF) > 0x9))) {
                                                adj += 0x6;
                                            }
                                            if ((CFlag != 0) || ((NFlag == 0) && (regA > 0x99))) {
                                                adj += 0x60;
                                                if (NFlag == 0) {
                                                    CFlag = 1;
                                                }
                                            }
                                            if (NFlag != 0) {
                                                regA = (regA - adj) & 0xFF;
                                            } else {
                                                regA = (regA + adj) & 0xFF;
                                            }
                                            nZFlag = regA;
                                            HFlag = 0;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0x2B) {
                                    if (opcode <= 0x29) {
                                        if (opcode <= 0x28) {
                                            // 0x28: JR Z,r8
                                            if (nZFlag == 0) {
                                                pc = (pc + 1 + ((busRead(pc) << 24) >> 24)) & 0xFFFF;
                                                cycleMClock(3);
                                            } else {
                                                pc++;
                                                cycleMClock(2);
                                            }
                                        } else {
                                            // 0x29: ADD HL,HL
                                            var HL = (regH << 8) | regL;
                                            var result = HL + HL;
                                            regH = (result >> 8) & 0xFF;
                                            regL = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (HL ^ HL ^ result) & 0x1000;
                                            CFlag = result & 0x10000;
                                            cycleMClock(2);
                                        }
                                    } else {
                                        if (opcode <= 0x2A) {
                                            // 0x2A: LDI A,(HL)
                                            var hl = (regH << 8) | regL;
                                            regA = busRead(hl);
                                            hl++;
                                            regH = (hl >> 8) & 0xFF;
                                            regL = hl & 0xFF;
                                            cycleMClock(2);
                                        } else {
                                            // 0x2B: DEC HL
                                            var result = ((regH << 8) | regL) - 1;
                                            regH = (result >> 8) & 0xFF;
                                            regL = result & 0xFF;
                                            cycleMClock(2);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x2D) {
                                        if (opcode <= 0x2C) {
                                            // 0x2C: INC L
                                            var result = regL + 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regL ^ result) & 0x10;
                                            regL = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x2D: DEC L
                                            var result = regL - 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regL ^ result) & 0x10;
                                            regL = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x2E) {
                                            // 0x2E: LD L,d8
                                            regL = busRead(pc);
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0x2F: CPL
                                            regA = (~regA) & 0xFF;
                                            NFlag = 1;
                                            HFlag = 1;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            }
                        } else {
                            if (opcode <= 0x37) {
                                if (opcode <= 0x33) {
                                    if (opcode <= 0x31) {
                                        if (opcode <= 0x30) {
                                            // 0x30: JR NC,r8
                                            if (CFlag == 0) {
                                                pc = (pc + 1 + ((busRead(pc) << 24) >> 24)) & 0xFFFF;
                                                cycleMClock(3);
                                            } else {
                                                pc++;
                                                cycleMClock(2);
                                            }
                                        } else {
                                            // 0x31: LD SP,d16
                                            var value = busRead(pc);
                                            pc++;
                                            value |= busRead(pc) << 8;
                                            pc++;
                                            sp = value & 0xFFFF;
                                            cycleMClock(3);
                                        }
                                    } else {
                                        if (opcode <= 0x32) {
                                            // 0x32: LDD (HL),A
                                            var hl = (regH << 8) | regL;
                                            busWrite(hl, regA);
                                            hl--;
                                            regH = (hl >> 8) & 0xFF;
                                            regL = hl & 0xFF;
                                            cycleMClock(2);
                                        } else {
                                            // 0x33: INC SP
                                            sp = (sp + 1) & 0xFFFF;
                                            cycleMClock(2);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x35) {
                                        if (opcode <= 0x34) {
                                            // 0x34: INC (HL)
                                            var HL = (regH << 8) | regL;
                                            var value = busRead(HL);
                                            var result = value + 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (value ^ result) & 0x10;
                                            busWrite(HL, result & 0xFF);
                                            cycleMClock(3);
                                        } else {
                                            // 0x35: DEC (HL)
                                            var HL = (regH << 8) | regL;
                                            var value = busRead(HL);
                                            var result = value - 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (value ^ result) & 0x10;
                                            busWrite(HL, result & 0xFF);
                                            cycleMClock(3);
                                        }
                                    } else {
                                        if (opcode <= 0x36) {
                                            // 0x36: LD (HL),d8
                                            busWrite((regH << 8) | regL, busRead(pc));
                                            pc++;
                                            cycleMClock(3);
                                        } else {
                                            // 0x37: SCF
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 1;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0x3B) {
                                    if (opcode <= 0x39) {
                                        if (opcode <= 0x38) {
                                            // 0x38: JR C,r8
                                            if (CFlag) {
                                                pc = (pc + 1 + ((busRead(pc) << 24) >> 24)) & 0xFFFF;
                                                cycleMClock(3);
                                            } else {
                                                pc++;
                                                cycleMClock(2);
                                            }
                                        } else {
                                            // 0x39: ADD HL,SP
                                            var HL = (regH << 8) | regL;
                                            var result = HL + sp;
                                            regH = (result >> 8) & 0xFF;
                                            regL = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (HL ^ sp ^ result) & 0x1000;
                                            CFlag = result & 0x10000;
                                            cycleMClock(2);
                                        }
                                    } else {
                                        if (opcode <= 0x3A) {
                                            // 0x3A: LDD A,(HL)
                                            var hl = (regH << 8) | regL;
                                            regA = busRead(hl);
                                            hl--;
                                            regH = (hl >> 8) & 0xFF;
                                            regL = hl & 0xFF;
                                            cycleMClock(2);
                                        } else {
                                            // 0x3B: DEC SP
                                            sp = (sp - 1) & 0xFFFF;
                                            cycleMClock(2);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x3D) {
                                        if (opcode <= 0x3C) {
                                            // 0x3C: INC A
                                            var result = regA + 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ result) & 0x10;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x3D: DEC A
                                            var result = regA - 1;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ result) & 0x10;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x3E) {
                                            // 0x3E: LD A,d8
                                            regA = busRead(pc);
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0x3F: CCF
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = (CFlag == 0) ? 1 : 0;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    if (opcode <= 0x5F) {
                        if (opcode <= 0x4F) {
                            if (opcode <= 0x47) {
                                if (opcode <= 0x43) {
                                    if (opcode <= 0x41) {
                                        if (opcode <= 0x40) {
                                            // 0x40: LD B,B
                                            cycleMClock(1);
                                        } else {
                                            // 0x41: LD B,C
                                            regB = regC;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x42) {
                                            // 0x42: LD B,D
                                            regB = regD;
                                            cycleMClock(1);
                                        } else {
                                            // 0x43: LD B,E
                                            regB = regE;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x45) {
                                        if (opcode <= 0x44) {
                                            // 0x44: LD B,H
                                            regB = regH;
                                            cycleMClock(1);
                                        } else {
                                            // 0x45: LD B,L
                                            regB = regL;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x46) {
                                            // 0x46: LD B,(HL)
                                            regB = busRead((regH << 8) | regL);
                                            cycleMClock(2);
                                        } else {
                                            // 0x47: LD B,A
                                            regB = regA;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0x4B) {
                                    if (opcode <= 0x49) {
                                        if (opcode <= 0x48) {
                                            // 0x48: LD C,B
                                            regC = regB;
                                            cycleMClock(1);
                                        } else {
                                            // 0x49: LD C,C
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x4A) {
                                            // 0x4A: LD C,D
                                            regC = regD;
                                            cycleMClock(1);
                                        } else {
                                            // 0x4B: LD C,E
                                            regC = regE;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x4D) {
                                        if (opcode <= 0x4C) {
                                            // 0x4C: LD C,H
                                            regC = regH;
                                            cycleMClock(1);
                                        } else {
                                            // 0x4D: LD C,L
                                            regC = regL;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x4E) {
                                            // 0x4E: LD C,(HL)
                                            regC = busRead((regH << 8) | regL);
                                            cycleMClock(2);
                                        } else {
                                            // 0x4F: LD C,A
                                            regC = regA;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            }
                        } else {
                            if (opcode <= 0x57) {
                                if (opcode <= 0x53) {
                                    if (opcode <= 0x51) {
                                        if (opcode <= 0x50) {
                                            // 0x50: LD D,B
                                            regD = regB;
                                            cycleMClock(1);
                                        } else {
                                            // 0x51: LD D,C
                                            regD = regC;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x52) {
                                            // 0x52: LD D,D
                                            cycleMClock(1);
                                        } else {
                                            // 0x53: LD D,E
                                            regD = regE;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x55) {
                                        if (opcode <= 0x54) {
                                            // 0x54: LD D,H
                                            regD = regH;
                                            cycleMClock(1);
                                        } else {
                                            // 0x55: LD D,L
                                            regD = regL;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x56) {
                                            // 0x56: LD D,(HL)
                                            regD = busRead((regH << 8) | regL);
                                            cycleMClock(2);
                                        } else {
                                            // 0x57: LD D,A
                                            regD = regA;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0x5B) {
                                    if (opcode <= 0x59) {
                                        if (opcode <= 0x58) {
                                            // 0x58: LD E,B
                                            regE = regB;
                                            cycleMClock(1);
                                        } else {
                                            // 0x59: LD E,C
                                            regE = regC;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x5A) {
                                            // 0x5A: LD E,D
                                            regE = regD;
                                            cycleMClock(1);
                                        } else {
                                            // 0x5B: LD E,E
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x5D) {
                                        if (opcode <= 0x5C) {
                                            // 0x5C: LD E,H
                                            regE = regH;
                                            cycleMClock(1);
                                        } else {
                                            // 0x5D: LD E,L
                                            regE = regL;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x5E) {
                                            // 0x5E: LD E,(HL)
                                            regE = busRead((regH << 8) | regL);
                                            cycleMClock(2);
                                        } else {
                                            // 0x5F: LD E,A
                                            regE = regA;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        if (opcode <= 0x6F) {
                            if (opcode <= 0x67) {
                                if (opcode <= 0x63) {
                                    if (opcode <= 0x61) {
                                        if (opcode <= 0x60) {
                                            // 0x60: LD H,B
                                            regH = regB;
                                            cycleMClock(1);
                                        } else {
                                            // 0x61: LD H,C
                                            regH = regC;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x62) {
                                            // 0x62: LD H,D
                                            regH = regD;
                                            cycleMClock(1);
                                        } else {
                                            // 0x63: LD H,E
                                            regH = regE;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x65) {
                                        if (opcode <= 0x64) {
                                            // 0x64: LD H,H
                                            cycleMClock(1);
                                        } else {
                                            // 0x65: LD H,L
                                            regH = regL;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x66) {
                                            // 0x66: LD H,(HL)
                                            regH = busRead((regH << 8) | regL);
                                            cycleMClock(2);
                                        } else {
                                            // 0x67: LD H,A
                                            regH = regA;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0x6B) {
                                    if (opcode <= 0x69) {
                                        if (opcode <= 0x68) {
                                            // 0x68: LD L,B
                                            regL = regB;
                                            cycleMClock(1);
                                        } else {
                                            // 0x69: LD L,C
                                            regL = regC;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x6A) {
                                            // 0x6A: LD L,D
                                            regL = regD;
                                            cycleMClock(1);
                                        } else {
                                            // 0x6B: LD L,E
                                            regL = regE;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x6D) {
                                        if (opcode <= 0x6C) {
                                            // 0x6C: LD L,H
                                            regL = regH;
                                            cycleMClock(1);
                                        } else {
                                            // 0x6D: LD L,L
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x6E) {
                                            // 0x6E: LD L,(HL)
                                            regL = busRead((regH << 8) | regL);
                                            cycleMClock(2);
                                        } else {
                                            // 0x6F: LD L,A
                                            regL = regA;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            }
                        } else {
                            if (opcode <= 0x77) {
                                if (opcode <= 0x73) {
                                    if (opcode <= 0x71) {
                                        if (opcode <= 0x70) {
                                            // 0x70: LD (HL),B
                                            busWrite((regH << 8) | regL, regB);
                                            cycleMClock(2);
                                        } else {
                                            // 0x71: LD (HL),C
                                            busWrite((regH << 8) | regL, regC);
                                            cycleMClock(2);
                                        }
                                    } else {
                                        if (opcode <= 0x72) {
                                            // 0x72: LD (HL),D
                                            busWrite((regH << 8) | regL, regD);
                                            cycleMClock(2);
                                        } else {
                                            // 0x73: LD (HL),E
                                            busWrite((regH << 8) | regL, regE);
                                            cycleMClock(2);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x75) {
                                        if (opcode <= 0x74) {
                                            // 0x74: LD (HL),H
                                            busWrite((regH << 8) | regL, regH);
                                            cycleMClock(2);
                                        } else {
                                            // 0x75: LD (HL),L
                                            busWrite((regH << 8) | regL, regL);
                                            cycleMClock(2);
                                        }
                                    } else {
                                        if (opcode <= 0x76) {
                                            // 0x76: HALT
                                            state = CPU_STATE_START_HALT;
                                            cycleMClock(1);
                                        } else {
                                            // 0x77: LD (HL),A
                                            busWrite((regH << 8) | regL, regA);
                                            cycleMClock(2);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0x7B) {
                                    if (opcode <= 0x79) {
                                        if (opcode <= 0x78) {
                                            // 0x78: LD A,B
                                            regA = regB;
                                            cycleMClock(1);
                                        } else {
                                            // 0x79: LD A,C
                                            regA = regC;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x7A) {
                                            // 0x7A: LD A,D
                                            regA = regD;
                                            cycleMClock(1);
                                        } else {
                                            // 0x7B: LD A,E
                                            regA = regE;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x7D) {
                                        if (opcode <= 0x7C) {
                                            // 0x7C: LD A,H
                                            regA = regH;
                                            cycleMClock(1);
                                        } else {
                                            // 0x7D: LD A,L
                                            regA = regL;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x7E) {
                                            // 0x7E: LD A,(HL)
                                            regA = busRead((regH << 8) | regL);
                                            cycleMClock(2);
                                        } else {
                                            // 0x7F: LD A,A
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                if (opcode <= 0xBF) {
                    if (opcode <= 0x9F) {
                        if (opcode <= 0x8F) {
                            if (opcode <= 0x87) {
                                if (opcode <= 0x83) {
                                    if (opcode <= 0x81) {
                                        if (opcode <= 0x80) {
                                            // 0x80: ADD A,B
                                            var result = regA + regB;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regB ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x81: ADD A,C
                                            var result = regA + regC;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regC ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x82) {
                                            // 0x82: ADD A,D
                                            var result = regA + regD;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regD ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x83: ADD A,E
                                            var result = regA + regE;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regE ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x85) {
                                        if (opcode <= 0x84) {
                                            // 0x84: ADD A,H
                                            var result = regA + regH;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regH ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x85: ADD A,L
                                            var result = regA + regL;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regL ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x86) {
                                            // 0x86: ADD A,(HL)
                                            var value = busRead((regH << 8) | regL);
                                            var result = regA + value;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ value ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(2);
                                        } else {
                                            // 0x87: ADD A,A
                                            var result = regA + regA;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regA ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0x8B) {
                                    if (opcode <= 0x89) {
                                        if (opcode <= 0x88) {
                                            // 0x88: ADC A,B
                                            var result = regA + regB + (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regB ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x89: ADC A,C
                                            var result = regA + regC + (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regC ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x8A) {
                                            // 0x8A: ADC A,D
                                            var result = regA + regD + (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regD ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x8B: ADC A,E
                                            var result = regA + regE + (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regE ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x8D) {
                                        if (opcode <= 0x8C) {
                                            // 0x8C: ADC A,H
                                            var result = regA + regH + (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regH ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x8D: ADC A,L
                                            var result = regA + regL + (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regL ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x8E) {
                                            // 0x8E: ADC A,(HL)
                                            var value = busRead((regH << 8) | regL);
                                            var result = regA + value + (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ value ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(2);
                                        } else {
                                            // 0x8F: ADC A,A
                                            var result = regA + regA + (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ regA ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            }
                        } else {
                            if (opcode <= 0x97) {
                                if (opcode <= 0x93) {
                                    if (opcode <= 0x91) {
                                        if (opcode <= 0x90) {
                                            // 0x90: SUB B
                                            var result = regA - regB;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regB ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x91: SUB C
                                            var result = regA - regC;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regC ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x92) {
                                            // 0x92: SUB D
                                            var result = regA - regD;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regD ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x93: SUB E
                                            var result = regA - regE;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regE ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x95) {
                                        if (opcode <= 0x94) {
                                            // 0x94: SUB H
                                            var result = regA - regH;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regH ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x95: SUB L
                                            var result = regA - regL;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regL ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x96) {
                                            // 0x96: SUB (HL)
                                            var value = busRead((regH << 8) | regL);
                                            var result = regA - value;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ value ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(2);
                                        } else {
                                            // 0x97: SUB A
                                            var result = regA - regA;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regA ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0x9B) {
                                    if (opcode <= 0x99) {
                                        if (opcode <= 0x98) {
                                            // 0x98: SBC A,B
                                            var result = regA - regB - (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regB ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x99: SBC A,C
                                            var result = regA - regC - (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regC ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x9A) {
                                            // 0x9A: SBC A,D
                                            var result = regA - regD - (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regD ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x9B: SBC A,E
                                            var result = regA - regE - (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regE ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0x9D) {
                                        if (opcode <= 0x9C) {
                                            // 0x9C: SBC A,H
                                            var result = regA - regH - (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regH ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        } else {
                                            // 0x9D: SBC A,L
                                            var result = regA - regL - (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regL ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0x9E) {
                                            // 0x9E: SBC A,(HL)
                                            var value = busRead((regH << 8) | regL);
                                            var result = regA - value - (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ value ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(2);
                                        } else {
                                            // 0x9F: SBC A,A
                                            var result = regA - regA - (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regA ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        if (opcode <= 0xAF) {
                            if (opcode <= 0xA7) {
                                if (opcode <= 0xA3) {
                                    if (opcode <= 0xA1) {
                                        if (opcode <= 0xA0) {
                                            // 0xA0: AND B
                                            regA &= regB;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 1;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        } else {
                                            // 0xA1: AND C
                                            regA &= regC;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 1;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0xA2) {
                                            // 0xA2: AND D
                                            regA &= regD;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 1;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        } else {
                                            // 0xA3: AND E
                                            regA &= regE;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 1;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0xA5) {
                                        if (opcode <= 0xA4) {
                                            // 0xA4: AND H
                                            regA &= regH;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 1;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        } else {
                                            // 0xA5: AND L
                                            regA &= regL;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 1;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0xA6) {
                                            // 0xA6: AND (HL)
                                            regA &= busRead((regH << 8) | regL);
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 1;
                                            CFlag = 0;
                                            cycleMClock(2);
                                        } else {
                                            // 0xA7: AND A
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 1;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0xAB) {
                                    if (opcode <= 0xA9) {
                                        if (opcode <= 0xA8) {
                                            // 0xA8: XOR B
                                            regA ^= regB;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        } else {
                                            // 0xA9: XOR C
                                            regA ^= regC;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0xAA) {
                                            // 0xAA: XOR D
                                            regA ^= regD;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        } else {
                                            // 0xAB: XOR E
                                            regA ^= regE;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0xAD) {
                                        if (opcode <= 0xAC) {
                                            // 0xAC: XOR H
                                            regA ^= regH;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        } else {
                                            // 0xAD: XOR L
                                            regA ^= regL;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0xAE) {
                                            // 0xAE: XOR (HL)
                                            regA ^= busRead((regH << 8) | regL);
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(2);
                                        } else {
                                            // 0xAF: XOR A
                                            regA = 0;
                                            nZFlag = 0;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            }
                        } else {
                            if (opcode <= 0xB7) {
                                if (opcode <= 0xB3) {
                                    if (opcode <= 0xB1) {
                                        if (opcode <= 0xB0) {
                                            // 0xB0: OR B
                                            regA |= regB;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        } else {
                                            // 0xB1: OR C
                                            regA |= regC;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0xB2) {
                                            // 0xB2: OR D
                                            regA |= regD;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        } else {
                                            // 0xB3: OR E
                                            regA |= regE;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0xB5) {
                                        if (opcode <= 0xB4) {
                                            // 0xB4: OR H
                                            regA |= regH;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        } else {
                                            // 0xB5: OR L
                                            regA |= regL;
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0xB6) {
                                            // 0xB6: OR (HL)
                                            regA |= busRead((regH << 8) | regL);
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(2);
                                        } else {
                                            // 0xB7: OR A
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0xBB) {
                                    if (opcode <= 0xB9) {
                                        if (opcode <= 0xB8) {
                                            // 0xB8: CP B
                                            var result = regA - regB;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regB ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            cycleMClock(1);
                                        } else {
                                            // 0xB9: CP C
                                            var result = regA - regC;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regC ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0xBA) {
                                            // 0xBA: CP D
                                            var result = regA - regD;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regD ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            cycleMClock(1);
                                        } else {
                                            // 0xBB: CP E
                                            var result = regA - regE;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regE ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0xBD) {
                                        if (opcode <= 0xBC) {
                                            // 0xBC: CP H
                                            var result = regA - regH;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regH ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            cycleMClock(1);
                                        } else {
                                            // 0xBD: CP L
                                            var result = regA - regL;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ regL ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0xBE) {
                                            // 0xBE: CP (HL)
                                            var value = busRead((regH << 8) | regL);
                                            var result = regA - value;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ value ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            cycleMClock(2);
                                        } else {
                                            // 0xBF: CP A
                                            nZFlag = 0;
                                            NFlag = 1;
                                            HFlag = 0;
                                            CFlag = 0;
                                            cycleMClock(1);
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    if (opcode <= 0xDF) {
                        if (opcode <= 0xCF) {
                            if (opcode <= 0xC7) {
                                if (opcode <= 0xC3) {
                                    if (opcode <= 0xC1) {
                                        if (opcode <= 0xC0) {
                                            // 0xC0: RET NZ
                                            if (nZFlag) {
                                                pc = busRead(sp);
                                                sp += 1;
                                                pc |= busRead(sp) << 8;
                                                sp += 1;
                                                cycleMClock(5);
                                            } else {
                                                cycleMClock(2);
                                            }
                                        } else {
                                            // 0xC1: POP BC
                                            regC = busRead(sp);
                                            sp += 1;
                                            regB = busRead(sp);
                                            sp += 1;
                                            cycleMClock(3);
                                        }
                                    } else {
                                        if (opcode <= 0xC2) {
                                            // 0xC2: JP NZ,a16
                                            if (nZFlag) {
                                                pc = (busRead(pc + 1) << 8) | busRead(pc);
                                                cycleMClock(4);
                                            } else {
                                                pc += 2;
                                                cycleMClock(3);
                                            }
                                        } else {
                                            // 0xC3: JP a16
                                            pc = (busRead(pc + 1) << 8) | busRead(pc);
                                            cycleMClock(4);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0xC5) {
                                        if (opcode <= 0xC4) {
                                            // 0xC4: CALL NZ,a16
                                            if (nZFlag) {
                                                var callAddr = busRead(pc);
                                                pc++;
                                                callAddr |= busRead(pc) << 8;
                                                pc++;
                                                sp--;
                                                busWrite(sp, pc >> 8);
                                                sp--;
                                                busWrite(sp, pc & 0xFF);
                                                pc = callAddr;
                                                cycleMClock(6);
                                            } else {
                                                pc += 2;
                                                cycleMClock(3);
                                            }
                                        } else {
                                            // 0xC5: PUSH BC
                                            sp -= 1;
                                            busWrite(sp, regB);
                                            sp -= 1;
                                            busWrite(sp, regC);
                                            cycleMClock(4);
                                        }
                                    } else {
                                        if (opcode <= 0xC6) {
                                            // 0xC6: ADD A,d8
                                            var value = busRead(pc);
                                            var result = regA + value;
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ value ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0xC7: RST 00H
                                            sp -= 1;
                                            busWrite(sp, pc >> 8);
                                            sp -= 1;
                                            busWrite(sp, pc & 0xFF);
                                            pc = 0x00;
                                            cycleMClock(4);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0xCB) {
                                    if (opcode <= 0xC9) {
                                        if (opcode <= 0xC8) {
                                            // 0xC8: RET Z
                                            if (nZFlag == 0) {
                                                pc = busRead(sp);
                                                sp += 1;
                                                pc |= busRead(sp) << 8;
                                                sp += 1;
                                                cycleMClock(5);
                                            } else {
                                                cycleMClock(2);
                                            }
                                        } else {
                                            // 0xC9: RET
                                            pc = busRead(sp);
                                            sp += 1;
                                            pc |= busRead(sp) << 8;
                                            sp += 1;
                                            cycleMClock(4);
                                        }
                                    } else {
                                        if (opcode <= 0xCA) {
                                            // 0xCA: JP Z,a16
                                            if (nZFlag == 0) {
                                                pc = (busRead(pc + 1) << 8) | busRead(pc);
                                                cycleMClock(4);
                                            } else {
                                                pc += 2;
                                                cycleMClock(3);
                                            }
                                        } else {
                                            // 0xCB: CB
                                            opcode = busRead(pc);
                                            pc++;
                                            doCBOP(opcode);
                                            // doCBOP mutates registers/flags via instance fields directly,
                                            // so refresh the cached locals to keep them in sync.
                                            regA = _regA;
                                            regB = _regB;
                                            regC = _regC;
                                            regD = _regD;
                                            regE = _regE;
                                            regH = _regH;
                                            regL = _regL;
                                            nZFlag = _nZFlag;
                                            NFlag = _NFlag;
                                            HFlag = _HFlag;
                                            CFlag = _CFlag;
                                        }
                                    }
                                } else {
                                    if (opcode <= 0xCD) {
                                        if (opcode <= 0xCC) {
                                            // 0xCC: CALL Z,a16
                                            if (nZFlag == 0) {
                                                var callAddr = busRead(pc);
                                                pc++;
                                                callAddr |= busRead(pc) << 8;
                                                pc++;
                                                sp--;
                                                busWrite(sp, pc >> 8);
                                                sp--;
                                                busWrite(sp, pc & 0xFF);
                                                pc = callAddr;
                                                cycleMClock(6);
                                            } else {
                                                pc += 2;
                                                cycleMClock(3);
                                            }
                                        } else {
                                            // 0xCD: CALL a16
                                            var callAddr = busRead(pc);
                                            pc++;
                                            callAddr |= busRead(pc) << 8;
                                            pc++;
                                            sp--;
                                            busWrite(sp, pc >> 8);
                                            sp--;
                                            busWrite(sp, pc & 0xFF);
                                            pc = callAddr;
                                            cycleMClock(6);
                                        }
                                    } else {
                                        if (opcode <= 0xCE) {
                                            // 0xCE: ADC A,d8
                                            var value = busRead(pc);
                                            var result = regA + value + (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 0;
                                            HFlag = (regA ^ value ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0xCF: RST 08H
                                            sp -= 1;
                                            busWrite(sp, pc >> 8);
                                            sp -= 1;
                                            busWrite(sp, pc & 0xFF);
                                            pc = 0x08;
                                            cycleMClock(4);
                                        }
                                    }
                                }
                            }
                        } else {
                            if (opcode <= 0xD7) {
                                if (opcode <= 0xD3) {
                                    if (opcode <= 0xD1) {
                                        if (opcode <= 0xD0) {
                                            // 0xD0: RET NC
                                            if (CFlag == 0) {
                                                pc = busRead(sp);
                                                sp += 1;
                                                pc |= busRead(sp) << 8;
                                                sp += 1;
                                                cycleMClock(5);
                                            } else {
                                                cycleMClock(2);
                                            }
                                        } else {
                                            // 0xD1: POP DE
                                            regE = busRead(sp);
                                            sp += 1;
                                            regD = busRead(sp);
                                            sp += 1;
                                            cycleMClock(3);
                                        }
                                    } else {
                                        if (opcode <= 0xD2) {
                                            // 0xD2: JP NC,a16
                                            if (CFlag == 0) {
                                                pc = (busRead(pc + 1) << 8) | busRead(pc);
                                                cycleMClock(4);
                                            } else {
                                                pc += 2;
                                                cycleMClock(3);
                                            }
                                        } else {
                                            // 0xD3: INVALID
                                            System.println("Opcode not implemented: 0x" + opcode.format("%02X"));
                                            throw new Lang.Exception();
                                        }
                                    }
                                } else {
                                    if (opcode <= 0xD5) {
                                        if (opcode <= 0xD4) {
                                            // 0xD4: CALL NC,a16
                                            if (CFlag == 0) {
                                                var callAddr = busRead(pc);
                                                pc++;
                                                callAddr |= busRead(pc) << 8;
                                                pc++;
                                                sp--;
                                                busWrite(sp, pc >> 8);
                                                sp--;
                                                busWrite(sp, pc & 0xFF);
                                                pc = callAddr;
                                                cycleMClock(6);
                                            } else {
                                                pc += 2;
                                                cycleMClock(3);
                                            }
                                        } else {
                                            // 0xD5: PUSH DE
                                            sp -= 1;
                                            busWrite(sp, regD);
                                            sp -= 1;
                                            busWrite(sp, regE);
                                            cycleMClock(4);
                                        }
                                    } else {
                                        if (opcode <= 0xD6) {
                                            // 0xD6: SUB d8
                                            var value = busRead(pc);
                                            var result = regA - value;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ value ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0xD7: RST 10H
                                            sp -= 1;
                                            busWrite(sp, pc >> 8);
                                            sp -= 1;
                                            busWrite(sp, pc & 0xFF);
                                            pc = 0x10;
                                            cycleMClock(4);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0xDB) {
                                    if (opcode <= 0xD9) {
                                        if (opcode <= 0xD8) {
                                            // 0xD8: RET C
                                            if (CFlag) {
                                                pc = busRead(sp);
                                                sp += 1;
                                                pc |= busRead(sp) << 8;
                                                sp += 1;
                                                cycleMClock(5);
                                            } else {
                                                cycleMClock(2);
                                            }
                                        } else {
                                            // 0xD9: RETI
                                            ime = true;
                                            pc = busRead(sp);
                                            sp += 1;
                                            pc |= busRead(sp) << 8;
                                            sp += 1;
                                            cycleMClock(4);
                                        }
                                    } else {
                                        if (opcode <= 0xDA) {
                                            // 0xDA: JP C,a16
                                            if (CFlag) {
                                                pc = (busRead(pc + 1) << 8) | busRead(pc);
                                                cycleMClock(4);
                                            } else {
                                                pc += 2;
                                                cycleMClock(3);
                                            }
                                        } else {
                                            // 0xDB: INVALID
                                            System.println("Opcode not implemented: 0x" + opcode.format("%02X"));
                                                throw new Lang.Exception();
                                        }
                                    }
                                } else {
                                    if (opcode <= 0xDD) {
                                        if (opcode <= 0xDC) {
                                            // 0xDC: CALL C,a16
                                            if (CFlag) {
                                                var callAddr = busRead(pc);
                                                pc++;
                                                callAddr |= busRead(pc) << 8;
                                                pc++;
                                                sp--;
                                                busWrite(sp, pc >> 8);
                                                sp--;
                                                busWrite(sp, pc & 0xFF);
                                                pc = callAddr;
                                                cycleMClock(6);
                                            } else {
                                                pc += 2;
                                                cycleMClock(3);
                                            }
                                        } else {
                                            // 0xDD: INVALID
                                            System.println("Opcode not implemented: 0x" + opcode.format("%02X"));
                                            throw new Lang.Exception();
                                        }
                                    } else {
                                        if (opcode <= 0xDE) {
                                            // 0xDE: SBC A,d8
                                            var value = busRead(pc);
                                            var result = regA - value - (CFlag ? 1 : 0);
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ value ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            regA = result & 0xFF;
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0xDF: RST 18H
                                            sp -= 1;
                                            busWrite(sp, pc >> 8);
                                            sp -= 1;
                                            busWrite(sp, pc & 0xFF);
                                            pc = 0x18;
                                            cycleMClock(4);
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        if (opcode <= 0xEF) {
                            if (opcode <= 0xE7) {
                                if (opcode <= 0xE3) {
                                    if (opcode <= 0xE1) {
                                        if (opcode <= 0xE0) {
                                            // 0xE0: LDH (a8),A
                                            busWrite(0xFF00 | busRead(pc), regA);
                                            pc++;
                                            cycleMClock(3);
                                        } else {
                                            // 0xE1: POP HL
                                            regL = busRead(sp);
                                            sp += 1;
                                            regH = busRead(sp);
                                            sp += 1;
                                            cycleMClock(3);
                                        }
                                    } else {
                                        if (opcode <= 0xE2) {
                                            // 0xE2: LD (C),A
                                            busWrite(0xFF00 | regC, regA);
                                            cycleMClock(2);
                                        } else {
                                            // 0xE3: INVALID
                                            System.println("Opcode not implemented: 0x" + opcode.format("%02X"));
                                            throw new Lang.Exception();
                                        }
                                    }
                                } else {
                                    if (opcode <= 0xE5) {
                                        if (opcode <= 0xE4) {
                                            // 0xE4: INVALID
                                            System.println("Opcode not implemented: 0x" + opcode.format("%02X"));
                                            throw new Lang.Exception();
                                        } else {
                                            // 0xE5: PUSH HL
                                            sp -= 1;
                                            busWrite(sp, regH);
                                            sp -= 1;
                                            busWrite(sp, regL);
                                            cycleMClock(4);
                                        }
                                    } else {
                                        if (opcode <= 0xE6) {
                                            // 0xE6: AND d8
                                            regA &= busRead(pc);
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 1;
                                            CFlag = 0;
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0xE7: RST 20H
                                            sp -= 1;
                                            busWrite(sp, pc >> 8);
                                            sp -= 1;
                                            busWrite(sp, pc & 0xFF);
                                            pc = 0x20;
                                            cycleMClock(4);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0xEB) {
                                    if (opcode <= 0xE9) {
                                        if (opcode <= 0xE8) {
                                            // 0xE8: ADD SP,r8
                                            var offset = (busRead(pc) << 24) >> 24;
                                            var result = sp + offset;

                                            var carry = sp ^ offset ^ result;
                                            nZFlag = 1;
                                            NFlag = 0;
                                            HFlag = carry & 0x10;
                                            CFlag = carry & 0x100;

                                            sp = result & 0xFFFF;
                                            pc++;
                                            cycleMClock(4);
                                        } else {
                                            // 0xE9: JP HL
                                            pc = (regH << 8) | regL;
                                            cycleMClock(1);
                                        }
                                    } else {
                                        if (opcode <= 0xEA) {
                                            // 0xEA: LD (a16),A
                                            var addr = busRead(pc);
                                            pc++;
                                            addr |= busRead(pc) << 8;
                                            pc++;
                                            busWrite(addr, regA);
                                            cycleMClock(4);
                                        } else {
                                            // 0xEB: INVALID
                                            System.println("Opcode not implemented: 0x" + opcode.format("%02X"));
                                            throw new Lang.Exception();
                                        }
                                    }
                                } else {
                                    if (opcode <= 0xED) {
                                        if (opcode <= 0xEC) {
                                            // 0xEC: INVALID
                                            System.println("Opcode not implemented: 0x" + opcode.format("%02X"));
                                            throw new Lang.Exception();
                                        } else {
                                            // 0xED: INVALID
                                            System.println("Opcode not implemented: 0x" + opcode.format("%02X"));
                                            throw new Lang.Exception();
                                        }
                                    } else {
                                        if (opcode <= 0xEE) {
                                            // 0xEE: XOR d8
                                            regA ^= busRead(pc);
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0xEF: RST 28H
                                            sp -= 1;
                                            busWrite(sp, pc >> 8);
                                            sp -= 1;
                                            busWrite(sp, pc & 0xFF);
                                            pc = 0x28;
                                            cycleMClock(4);
                                        }
                                    }
                                }
                            }
                        } else {
                            if (opcode <= 0xF7) {
                                if (opcode <= 0xF3) {
                                    if (opcode <= 0xF1) {
                                        if (opcode <= 0xF0) {
                                            // 0xF0: LDH A,(a8)
                                            regA = busRead(0xFF00 | busRead(pc));
                                            pc++;
                                            cycleMClock(3);
                                        } else {
                                            // 0xF1: POP AF
                                            var popData = busRead(sp);
                                            nZFlag = ((popData & 0x80) == 0) ? 1 : 0;
                                            NFlag = popData & 0x40;
                                            HFlag = popData & 0x20;
                                            CFlag = popData & 0x10;
                                            sp += 1;
                                            regA = busRead(sp);
                                            sp += 1;
                                            cycleMClock(3);
                                        }
                                    } else {
                                        if (opcode <= 0xF2) {
                                            // 0xF2: LD A,(C)
                                            regA = busRead(0xFF00 | regC);
                                            cycleMClock(2);
                                        } else {
                                            // 0xF3: DI
                                            ime = false;
                                            imeNext = false;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0xF5) {
                                        if (opcode <= 0xF4) {
                                            // 0xF4: INVALID
                                            System.println("Opcode not implemented: 0x" + opcode.format("%02X"));
                                            throw new Lang.Exception();
                                        } else {
                                            // 0xF5: PUSH AF
                                            var pushData = (nZFlag == 0) ? 0x80 : 0x00;
                                            pushData |= (NFlag) ? 0x40 : 0x00;
                                            pushData |= (HFlag) ? 0x20 : 0x00;
                                            pushData |= (CFlag) ? 0x10 : 0x00;
                                            sp -= 1;
                                            busWrite(sp, regA);
                                            sp -= 1;
                                            busWrite(sp, pushData);
                                            cycleMClock(4);
                                        }
                                    } else {
                                        if (opcode <= 0xF6) {
                                            // 0xF6: OR d8
                                            regA |= busRead(pc);
                                            nZFlag = regA;
                                            NFlag = 0;
                                            HFlag = 0;
                                            CFlag = 0;
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0xF7: RST 30H
                                            sp -= 1;
                                            busWrite(sp, pc >> 8);
                                            sp -= 1;
                                            busWrite(sp, pc & 0xFF);
                                            pc = 0x30;
                                            cycleMClock(4);
                                        }
                                    }
                                }
                            } else {
                                if (opcode <= 0xFB) {
                                    if (opcode <= 0xF9) {
                                        if (opcode <= 0xF8) {
                                            // 0xF8: LD HL,SP+r8
                                            var offset = (busRead(pc) << 24) >> 24; // Convert to 32 bit signed
                                            var result = sp + offset;
                                            regH = (result >> 8) & 0xFF;
                                            regL = result & 0xFF;

                                            var carry = sp ^ offset ^ result;
                                            nZFlag = 1;
                                            NFlag = 0;
                                            HFlag = carry & 0x10;
                                            CFlag = carry & 0x100;
                                            pc++;
                                            cycleMClock(3);
                                        } else {
                                            // 0xF9: LD SP,HL
                                            sp = (regH << 8) | regL;
                                            cycleMClock(2);
                                        }
                                    } else {
                                        if (opcode <= 0xFA) {
                                            // 0xFA: LD A,(a16)
                                            var addr = busRead(pc);
                                            pc++;
                                            addr |= busRead(pc) << 8;
                                            pc++;
                                            regA = busRead(addr);
                                            cycleMClock(4);
                                        } else {
                                            // 0xFB: EI
                                            imeNext = true;
                                            cycleMClock(1);
                                        }
                                    }
                                } else {
                                    if (opcode <= 0xFD) {
                                        if (opcode <= 0xFC) {
                                            // 0xFC: INVALID
                                            System.println("Opcode not implemented: 0x" + opcode.format("%02X"));
                                            throw new Lang.Exception();
                                        } else {
                                            // 0xFD: INVALID
                                            System.println("Opcode not implemented: 0x" + opcode.format("%02X"));
                                            throw new Lang.Exception();
                                        }
                                    } else {
                                        if (opcode <= 0xFE) {
                                            // 0xFE: CP d8
                                            var value = busRead(pc);
                                            var result = regA - value;
                                            nZFlag = result & 0xFF;
                                            NFlag = 1;
                                            HFlag = (regA ^ value ^ result) & 0x10;
                                            CFlag = result & 0x100;
                                            pc++;
                                            cycleMClock(2);
                                        } else {
                                            // 0xFF: RST 38H
                                            sp -= 1;
                                            busWrite(sp, pc >> 8);
                                            sp -= 1;
                                            busWrite(sp, pc & 0xFF);
                                            pc = 0x38;
                                            cycleMClock(4);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }


            // Don't process imeNext if Op EI just ran
            if (imeNext && opcode != 0xFB) {
                imeNext = false;
                ime = true;
            }
        }
        _state = state;
        _pc = pc;
        _sp = sp;
        _nZFlag = nZFlag;
        _NFlag = NFlag;
        _HFlag = HFlag;
        _CFlag = CFlag;
        _ime = ime;
        _imeNext = imeNext;
        _ie = ie;
        _regA = regA;
        _regB = regB;
        _regC = regC;
        _regD = regD;
        _regE = regE;
        _regH = regH;
        _regL = regL;
        _lastWaitTime = System.getTimer();
    }


    private function getRegByIndex(index as Number) as Number {
        switch (index) {
            case REG_B: return _regB;
            case REG_C: return _regC;
            case REG_D: return _regD;
            case REG_E: return _regE;
            case REG_H: return _regH;
            case REG_L: return _regL;
            case REG_A: return _regA;
            default:
                System.println("Invalid register index: " + index);
                throw new Lang.Exception();
        }
    }

    private function setRegByIndex(index as Number, value as Number) as Void {
        switch (index) {
            case REG_B: _regB = value; break;
            case REG_C: _regC = value; break;
            case REG_D: _regD = value; break;
            case REG_E: _regE = value; break;
            case REG_H: _regH = value; break;
            case REG_L: _regL = value; break;
            case REG_A: _regA = value; break;
            default:
                System.println("Invalid register index: " + index);
                throw new Lang.Exception();
        }
    }

    // TODO: Rework this to be faster
    private function doCBOP(opcode as Number) as Void {
        var regIndex = opcode & 0x07;
        var opType = (opcode >> 3) & 0x07;
        var group = opcode >> 6;
        var isHL = regIndex == 6;
        var value = isHL ? busRead((_regH << 8) | _regL) : getRegByIndex(regIndex);
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
                busWrite((_regH << 8) | _regL, result);
                cycleMClock(4);
            } else {
                setRegByIndex(regIndex, result);
                cycleMClock(2);
            }
        } else {
            if (isHL) {
                cycleMClock(3);
            } else {
                cycleMClock(2);
            }
        }
    }

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