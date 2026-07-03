import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Timer;

typedef GBBusRead as Method(addr as Number) as Number;
typedef GBBusWrite as Method(addr as Number, data as Number) as Void;
typedef GBClockCycle as Method() as Void;

class GameBoy {
    enum Event {
        EVENT_READY,
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
    private var _cpu as GameBoyCPU?;
    private var _timer as GameBoyTimer?;
    private var _ppu as GameBoyPPU?;
    private var _serial as GameBoySerial?;
    private var _wram as ByteArray = new[8192]b;
    private var _dummyAudio as ByteArray = new[48]b;
    private var _joypadDirection as Number = 0xFF;
    private var _joypadAction as Number = 0xFF;
    private var _joyp as Number = 0x3F;
    private var _bootRomRequest as ExternalDataRequester;
    private var _eventCB as Method(Event) as Void;
    private var _mainTimer as Timer.Timer = new Timer.Timer();
    private var _lastTime as Number = 0;
    private var _cycleCount as Number = 0;

    function bootRomReady(data as ByteArray, requestString as String) as Void {
        _cpu = new GameBoyCPU(data, method(:busRead), method(:busWrite), method(:cycleMClock));
        _timer = new GameBoyTimer((_cpu as GameBoyCPU).method(:sendInt));
        _ppu = new GameBoyPPU((_cpu as GameBoyCPU).method(:sendInt), method(:ppuFrameDone));
        _serial = new GameBoySerial((_cpu as GameBoyCPU).method(:sendInt));
        _eventCB.invoke(EVENT_READY);
    }

    function ppuFrameDone() as Void {
        _eventCB.invoke(EVENT_FRAME_DONE);
    }

    function busRead(addr as Number) as Number {
        if (addr < 0x8000 && _cart != null) {
            // ROM
            return _cart.busRead(addr);
        } else if (addr < 0xA000) {
            // VRAM
            return (_ppu as GameBoyPPU).busRead(addr);
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
            return (_ppu as GameBoyPPU).busRead(addr);
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
                return (_serial as GameBoySerial).busRead(addr);
            } else {
                return 0xFF;
            }
        } else if (addr < 0xFF08) {
            // Timer registers
            return (_timer as GameBoyTimer).busRead(addr);
        } else if (addr < 0xFF40) {
            // Audio (dummied out by acting as normal ram)
            return _dummyAudio[addr - 0xFF10];
        } else if (addr < 0xFF4C) {
            // LCD
            return (_ppu as GameBoyPPU).busRead(addr);
        }
        return 0xFF;
    }

    function busWrite(addr as Number, data as Number) as Void {
        if (addr < 0x8000 && _cart != null) {
            // ROM
            _cart.busWrite(addr, data);
        } else if (addr < 0xA000) {
            // VRAM
            (_ppu as GameBoyPPU).busWrite(addr, data);
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
            (_ppu as GameBoyPPU).busWrite(addr, data);
        } else if (addr == 0xFF00) {
            // Joypad Input
            _joyp = (data & 0x30) | 0x0F;
        } else if (PRINT_SERIAL && addr < 0xFF03) {
            // Serial Transfer
            (_serial as GameBoySerial).busWrite(addr, data);
        } else if (addr < 0xFF08) {
            // Timer registers
            (_timer as GameBoyTimer).busWrite(addr, data);
        } else if (addr < 0xFF40) {
            // Audio (dummied out by acting as normal ram)
            _dummyAudio[addr - 0xFF10] = data;
        } else if (addr < 0xFF4C) {
            // LCD
            (_ppu as GameBoyPPU).busWrite(addr, data);
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
        var startTime = 0;
        var waitTimeDelta = 0;
        if (PRINT_SPEED) {
            _cycleCount = 0;
            startTime = System.getTimer();
            waitTimeDelta = startTime - _lastTime; 
        }

        for (var i = 0; i < STEPS_PER_CYCLE; i++) {
            (_cpu as GameBoyCPU).step();
        }

        if (PRINT_SPEED) {
            _lastTime = System.getTimer();
            var exeTimeDelta = _lastTime - startTime;
            var speed = (_cycleCount * 1000) / (exeTimeDelta + waitTimeDelta);
            System.println(format("Utilization: $1$% | $2$ MCycle/s", 
                [((exeTimeDelta * 100) / (exeTimeDelta + waitTimeDelta)).format("%d"), speed.format("%d")]
            ));
        }
    }

    function cycleMClock() as Void {
        (_timer as GameBoyTimer).step();
        (_ppu as GameBoyPPU).step();
        (_serial as GameBoySerial).step();
        if (PRINT_SPEED) {
            _cycleCount++;
        }
    }

    function initialize(eventCB as Method(Event) as Void) {
        _eventCB = eventCB;
        _bootRomRequest = new ExternalDataRequester(method(:bootRomReady));
    }

    function initSystem() as Void {
        if (_cpu == null) {
            _bootRomRequest.getData("boot-rom");
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
        return (_ppu as GameBoyPPU).getBitmap();
    } 

    function pressButton(bttn as Button) as Void {
        var prev = busRead(0xFF00);
        if (bttn > BUTTON_START) {
            bttn >>= 4;
            _joypadDirection &= ~bttn;
            if (prev != busRead(0xFF00)) {
                (_cpu as GameBoyCPU).sendInt(GameBoyCPU.INT_JOYPAD);
            }
        } else {
            _joypadAction &= ~bttn;
        }
        if (prev != busRead(0xFF00)) {
            (_cpu as GameBoyCPU).sendInt(GameBoyCPU.INT_JOYPAD);
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