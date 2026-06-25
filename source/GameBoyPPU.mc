import Toybox.Lang;
import Toybox.Graphics;

class GameBoyPPU {
    const OBJ_LIM = 10;
    const OBJ_WIDTH = 8;
    const SCREEN_WIDTH = 160;
    const SCREEN_HEIGHT = 144;
    const VBLANK_LINES = 10;
    private enum PPUMode {
        PPUMODE_HBLANK = 0,
        PPUMODE_VBLANK = 1,
        PPUMODE_OAM_SCAN = 2,
        PPUMODE_DRAW = 3
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

    private var _sendCPUInt as GBCPUSendIntFunc;
    private var _bitmap as BufferedBitmap;
    private var _prevIntState as Boolean = false;
    private var _vram as ByteArray = new ByteArray();
    private var _oam as ByteArray = new ByteArray();
    private var _lcdc as Number = 0; // LCD Control
    private var _ly as Number = 0; // LCD Y Cord
    private var _lyc as Number = 0; // LY Compare
    private var _ppuModeTick as Number = PPUCYCLE_OAM_SCAN;
    private var _ppuMode as Number = PPUMODE_OAM_SCAN;
    private var _stat as Number = 0; // LCD Status
    private var _scy as Number = 0; // Background Viewport Y
    private var _scx as Number = 0; // Background Viewport X
    private var _bgp as Number = 0; // Background Palette Data
    private var _obp as Array<Number> = [0, 0]; // OBJ Palette Data 
    private var _colorMap as Array<Graphics.ColorValue> = [Graphics.COLOR_WHITE, Graphics.COLOR_LT_GRAY, Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK];
    private var _wy as Number = 0; // Window Y Pos
    private var _wx as Number = 0; // Window X Pos

    private function drawLine() as Void {
        var selOBJs = new[0];

        // Get OBJs on line
        if (_lcdc & LCDCBIT_OBJ_EN) {
            var objHeight = (_lcdc & LCDCBIT_OBJ_SIZE) ? 16 : 8; 
            for (var oamIdx = 0; oamIdx < 160; oamIdx += 4) {
                var objYScreen = _oam[oamIdx + OBJBYTE_Y_POS] - 17;
                if (objYScreen <= _ly && _ly < (objYScreen + objHeight)) {
                    selOBJs.add(oamIdx);
                    if (selOBJs.size() == OBJ_LIM) {
                        // Reached OBJ Limit per Line
                        break;
                    }
                }
            }
        }

        var objsFound = selOBJs.size();
        var objStartIdx = 0;
        for (var lineX = 0; lineX < SCREEN_WIDTH; lineX++) {
            var objColor = null;
            var objColorIdx = null;
            var objPriority = null;
            for (var objIdx = objStartIdx; objIdx < objsFound; objIdx++) {
                var objOAMIdx = selOBJs[objIdx];
                var objX = _oam[objOAMIdx + OBJBYTE_X_POS];
                if (objX <= lineX) {
                    if (lineX < (objX + OBJ_WIDTH)) {
                        // Found possible OBJ
                        
                    } else {
                        // If we reach here we are past the obj, update start 
                        // idx so we don't iterate over this obj again
                        objStartIdx = objIdx;
                    }
                }
            }
        }
    }

    private function checkStat() as Void {
        var statTriggers = (((_lyc == _ly) ? 0x1 : 0x0) << 6) | (0x1 << (3 + _ppuMode));
        statTriggers &= _stat;
        var triggered = statTriggers != 0;

        if (triggered && !_prevIntState) {
            // Only interrupt on rising edge
            _sendCPUInt.invoke(GameBoyCPU.INT_LCD);
        }
        _prevIntState = triggered;
    }

    function initialize(sendCPUInt as GBCPUSendIntFunc) {
        _sendCPUInt = sendCPUInt;
        var bitmap = Graphics.createBufferedBitmap({
            :width => SCREEN_WIDTH,
            :height => SCREEN_HEIGHT
        }).get();

        if (bitmap != null) {
            _bitmap = bitmap as Graphics.BufferedBitmap;
        } else {
            // Failed to create PPU bitmap
            throw new Lang.Exception();
        }

        // Fill VRAM
        for (var i = 0; i < 8192; i++) {
            _vram.add(0);
        }
        // Fill OAM
        for (var i = 0; i < 160; i++) {
            _oam.add(0);
        }
    }

    function getBitmap() as BufferedBitmap {
        return _bitmap;
    }

    function step(mCycles as Number) as Void {
        if ((_lcdc & 0x80) == 0) {
            return;
        }

        _ppuModeTick--;
        if (_ppuModeTick == 0) {
            switch (_ppuMode) {
                case PPUMODE_OAM_SCAN: {
                    _ppuMode = PPUMODE_DRAW;
                    _ppuModeTick = PPUCYCLE_DRAW;
                    drawLine();
                    break;
                }

                case PPUMODE_DRAW: {
                    _ppuMode = PPUMODE_HBLANK;
                    _ppuModeTick = PPUCYCLE_HBLANK;
                    break;
                }

                case PPUMODE_HBLANK: {
                    _ly++;
                    if (_ly == SCREEN_HEIGHT) {
                        _ppuMode = PPUMODE_VBLANK;
                        _ppuModeTick = PPUCYCLE_VBLANK;
                    } else {
                        _ppuMode = PPUMODE_OAM_SCAN;
                        _ppuModeTick = PPUCYCLE_OAM_SCAN;
                    }
                    break;
                }

                case PPUMODE_VBLANK: {
                    _ly++;
                    if (_ly == (SCREEN_HEIGHT + VBLANK_LINES)) {
                        _ly = 0;
                        _ppuMode = PPUMODE_OAM_SCAN;
                        _ppuModeTick = PPUCYCLE_OAM_SCAN;
                    } else {
                        _ppuModeTick = PPUCYCLE_VBLANK;
                    }
                    break;
                }
            }
            // Check for STAT interrupt
            checkStat();
        }
    }

    function busRequest(addr as Number, data as Number?) as Number {
        if (addr < 0xA000) {
            // VRAM
            if (data == null) {
                return _vram[addr - 0x8000];
            } else {
                _vram[addr - 0x8000] = data;
            }
        } else if (addr < 0xFEA0) {
            // OAM
            if (data == null) {
                return _oam[addr - 0xFE00];
            } else {
                _oam[addr - 0xFE00] = data;
            }
        } else if (addr == 0xFF40) {
            // LCD Control
            if (data == null) {
                return _lcdc;
            } else {
                if ((data & LCDCBIT_LCD_EN) == 0) {
                    // Reset PPU if disabled
                    _ppuMode = PPUMODE_OAM_SCAN;
                    _ppuModeTick = PPUCYCLE_OAM_SCAN;
                    _ly = 0;
                }
                _lcdc = data;
            }
        } else if (addr == 0xFF41) {
            // LCD Status
            if (data == null) {
                _stat = (_stat & ~(0x7)) | (((_lyc == _ly) ? 0x1 : 0x0) << 2) | _ppuMode;
                return _stat;
            } else {
                _stat = data;
            }
        } else if (addr == 0xFF42) {
            // Background Viewport Y
            if (data == null) {
                return _scy;
            } else {
                _scy = data;
            }
        } else if (addr == 0xFF43) {
            // Background Viewport X
            if (data == null) {
                return _scx;
            } else {
                _scx = data;
            }
        } else if (addr == 0xFF44) {
            // LCD Y Cord
            return _ly;
        } else if (addr == 0xFF45) {
            // LY Compare
            if (data == null) {
                return _lyc;
            } else {
                _lyc = data;
            }
        } else if (addr == 0xFF47) {
            // BG Palette Data
            if (data == null) {
                return _bgp;
            } else {
                _bgp = data;
            }
        } else if (addr < 0xFF4A) {
            // OBJ Palette Data
            if (data == null) {
                return _obp[addr - 0xFF48];
            } else {
                _obp[addr - 0xFF48] = data;
            }
        } else if (addr == 0xFF4A) {
            // Window Y Pos
            if (data == null) {
                return _wy;
            } else {
                _wy = data;
            }
        } else if (addr == 0xFF4B) {
            // Window X Pos
            if (data == null) {
                return _wx;
            } else {
                _wx = data;
            }
        }
        return 0xFF;
    }
}