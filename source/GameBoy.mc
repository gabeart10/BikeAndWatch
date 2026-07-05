import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Timer;

typedef GBBusRead as Method(addr as Number) as Number;
typedef GBBusWrite as Method(addr as Number, data as Number) as Void;
typedef GBClockCycle as Method() as Void;

class GameBoy {
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

    private var _cart as GameCart.GameCart?;
    private var _cpu as GameBoyCPU = new GameBoyCPU(method(:busRead), method(:busWrite), method(:cycleMClock));
    private var _timer as GameBoyTimer = new GameBoyTimer(_cpu.method(:sendInt));
    private var _ppu as GameBoyPPU = new GameBoyPPU(_cpu.method(:sendInt), method(:ppuFrameDone));
    private var _serial as GameBoySerial = new GameBoySerial(_cpu.method(:sendInt));
    private var _wram as ByteArray = new[8192]b;
    private var _dummyAudio as ByteArray = new[48]b;
    private var _joypadDirection as Number = 0xFF;
    private var _joypadAction as Number = 0xFF;
    private var _joyp as Number = 0xCF;
    private var _eventCB as Method(Event) as Void;
    private var _mainTimer as Timer.Timer = new Timer.Timer();
    private var _lastTime as Number = 0;
    private var _cycleCount as Number = 0;

    function ppuFrameDone() as Void {
        _eventCB.invoke(EVENT_FRAME_DONE);

        if (PRINT_FPS) {
            var frameTimeDelta = System.getTimer() - _lastTime;
            _lastTime = System.getTimer();
            var renderFPS = 1000.0 / frameTimeDelta;
            if (PRINT_MCPS) {
                System.println(format("$1$ Render FPS | $2$ System FPS | $3$ MCycle/s", [
                    renderFPS.format("%.3f"), 
                    (renderFPS * PPU_FRAME_DIVIDER).format("%.3f"),
                    ((_cycleCount * 1000) / frameTimeDelta).format("%d")
                ]));
                _cycleCount = 0;
            } else {
                System.println(format("$1$ Render FPS | $2$ System FPS", [
                    renderFPS.format("%.3f"), 
                    (renderFPS * PPU_FRAME_DIVIDER).format("%.3f")
                ]));
            }
        }
    }

    function busRead(addr as Number) as Number {
        if (addr < 0x8000 && _cart != null) {
            // ROM
            return _cart.busRead(addr);
        } else if (addr < 0xA000) {
            // VRAM
            return _ppu.busRead(addr);
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
            return _ppu.busRead(addr);
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
            // Serial Transfer
            if (PRINT_SERIAL) {
                return _serial.busRead(addr);
            } else {
                return 0xFF;
            }
        } else if (addr < 0xFF08) {
            // Timer registers
            return _timer.busRead(addr);
        } else if (addr < 0xFF40) {
            // Audio (dummied out by acting as normal ram)
            return _dummyAudio[addr - 0xFF10];
        } else if (addr < 0xFF4C) {
            // LCD
            return _ppu.busRead(addr);
        }
        return 0xFF;
    }

    function busWrite(addr as Number, data as Number) as Void {
        if (addr < 0x8000 && _cart != null) {
            // ROM
            _cart.busWrite(addr, data);
        } else if (addr < 0xA000) {
            // VRAM
            _ppu.busWrite(addr, data);
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
            _ppu.busWrite(addr, data);
        } else if (addr == 0xFF00) {
            // Joypad Input
            _joyp = (data & 0x30) | 0xCF;
        } else if (PRINT_SERIAL && addr < 0xFF03) {
            // Serial Transfer
            _serial.busWrite(addr, data);
        } else if (addr < 0xFF08) {
            // Timer registers
            _timer.busWrite(addr, data);
        } else if (addr < 0xFF40) {
            // Audio (dummied out by acting as normal ram)
            _dummyAudio[addr - 0xFF10] = data;
        } else if (addr < 0xFF4C) {
            // LCD
            _ppu.busWrite(addr, data);
        } else if (addr == 0xFF46) {
            // OAM DMA
            var src = data << 8;
            for (var dest = 0xFE00; dest < 0xFEA0; dest++) {
                (_ppu as GameBoyPPU).busWrite(dest, busRead(src));
                src++;
            }
        }
    }

    function emuCycle() as Void {
        var cpuStep = _cpu.method(:step);
        for (var i = 0; i < STEPS_PER_CYCLE; i++) {
            cpuStep.invoke();
        }
    }

    function cycleMClock() as Void {
        _timer.step();
        _ppu.step();
        if (PRINT_SERIAL) {
            _serial.step();
        }
        if (PRINT_FPS && PRINT_MCPS) {
            _cycleCount++;
        }
    }

    function initialize(eventCB as Method(Event) as Void) {
        _eventCB = eventCB;
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
        return _ppu.getBitmap();
    } 

    function pressButton(bttn as Button) as Void {
        var prev = busRead(0xFF00);
        if (bttn > BUTTON_START) {
            bttn >>= 4;
            _joypadDirection &= ~bttn;
            if (prev != busRead(0xFF00)) {
                _cpu.sendInt(GameBoyCPU.INT_JOYPAD);
            }
        } else {
            _joypadAction &= ~bttn;
        }
        if (prev != busRead(0xFF00)) {
            _cpu.sendInt(GameBoyCPU.INT_JOYPAD);
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
}