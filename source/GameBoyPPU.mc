import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;

class GameBoyPPU {
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

    private var _frameDoneCB as Method() as Void;
    private var _frameSkipCount as Number = 0;
    private var _sendCPUInt as GBCPUSendIntFunc;
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

    function initialize(sendCPUInt as GBCPUSendIntFunc, frameDoneCB as Method() as Void) {
        _sendCPUInt = sendCPUInt;
        _frameDoneCB = frameDoneCB;
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

    function getBitmap() as BufferedBitmap {
        return _bitmap;
    }

    function step() as Void {
        if ((_lcdc & 0x80) == 0) {
            return;
        }
        
        _ppuModeTick--;
        if (_ppuModeTick == 0) {
            switch (_ppuMode) {
                case PPUMODE_OAM_SCAN: {
                    _ppuMode = PPUMODE_DRAW;
                    _ppuModeStat = STAT_INT_DRAW;
                    _ppuModeTick = PPUCYCLE_DRAW;
                    break;
                }

                case PPUMODE_DRAW: {
                    if (_ly == _wy) {
                        _yCond = true;
                    }
                    if (_frameSkipCount == 0) {
                        drawLine();
                    }
                    _ppuMode = PPUMODE_HBLANK;
                    _ppuModeStat = STAT_INT_HBLANK; 
                    _ppuModeTick = PPUCYCLE_HBLANK;
                    break;
                }

                case PPUMODE_HBLANK: {
                    _ly++;
                    if (_ly == SCREEN_HEIGHT) {
                        if (_frameSkipCount == 0) {
                            _frameDoneCB.invoke();
                        }
                        _sendCPUInt.invoke(GameBoyCPU.INT_VBLANK);
                        _ppuMode = PPUMODE_VBLANK;
                        _ppuModeStat = STAT_INT_VBLANK;
                        _ppuModeTick = PPUCYCLE_VBLANK;
                    } else {
                        _ppuMode = PPUMODE_OAM_SCAN;
                        _ppuModeStat = STAT_INT_OAM_SCAN;
                        _ppuModeTick = PPUCYCLE_OAM_SCAN;
                    }
                    break;
                }

                case PPUMODE_VBLANK: {
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
                    break;
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
                _sendCPUInt.invoke(GameBoyCPU.INT_LCD);
            }
            _prevIntState = triggered;
        }
    }

    function busRead(addr as Number) as Number {
        if (addr < 0xA000) {
            // VRAM
            return _vram[addr - 0x8000];
        } else if (addr < 0xFEA0) {
            // OAM
            return _oam[addr - 0xFE00];
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
        }
        return 0xFF;
    }

    function busWrite(addr as Number, data as Number) as Void {
        if (addr < 0xA000) {
            // VRAM
            _vram[addr - 0x8000] = data;
        } else if (addr < 0xFEA0) {
            // OAM
            _oam[addr - 0xFE00] = data;
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
        }
    }
}