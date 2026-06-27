import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Timer;

typedef GBBusRead as Method(addr as Number) as Number;
typedef GBBusWrite as Method(addr as Number, data as Number) as Void;
typedef GBClockCycle as Method(mCycles as Number) as Void;

const DEBUG_MODE as Boolean = false;
const START_MCPC as Number = 1000;
const TARGET_EXEC_TIME_MS as Number = 190;
const CYCLE_PER_MS_ADJUST as Number = 8;
const EMU_CYCLE_MS as Number = 200;

class GameBoy {
    enum Event {
        EVENT_READY,
        EVENT_FRAME_DONE
    }

    private var _cart as GameCart?;
    private var _cpu as GameBoyCPU?;
    private var _timer as GameBoyTimer?;
    private var _ppu as GameBoyPPU?;
    private var _wram as ByteArray = new[4096]b;
    private var _dummyAudio as ByteArray = new[23]b;
    private var _joyp as Number = 0x0F;
    private var _bootRomRequest as ExternalDataRequester;
    private var _eventCB as Method(Event) as Void;
    private var _mainTimer as Timer.Timer = new Timer.Timer();
    private var _lastTime as Number = 0;
    private var _mCyclePerCycle as Number = START_MCPC;

    function bootRomReady(data as ByteArray, requestString as String) as Void {
        _cpu = new GameBoyCPU(data, method(:busRead), method(:busWrite), method(:cycleMClock));
        _timer = new GameBoyTimer((_cpu as GameBoyCPU).method(:sendInt));
        _ppu = new GameBoyPPU((_cpu as GameBoyCPU).method(:sendInt), method(:ppuFrameDone));
        _eventCB.invoke(EVENT_READY);
    }

    function ppuFrameDone() as Void {
        _eventCB.invoke(EVENT_FRAME_DONE);
    }

    function busRead(addr as Number) as Number {
        if (addr < 0x8000 && _cart != null) {
            // ROM
            return _cart.readByte(addr);
        } else if (addr < 0xA000) {
            // VRAM
            return (_ppu as GameBoyPPU).busRead(addr);
        } else if (addr < 0xC000) {
            // External Ram
            return 0xFF;
        } else if (addr < 0xD000) {
            // WRAM
            return _wram[addr - 0xC000];
        } else if (addr < 0xFE00) {
            // Echo WRAM
            return _wram[addr - 0xE000];
        } else if (addr < 0xFEA0) {
            // OAM
            return (_ppu as GameBoyPPU).busRead(addr, data);
        } else if (addr == 0xFF00) {
            // Joypad Input
            return _joyp;
        } else if (addr < 0xFF03) {
            // Serial Transfer
            return 0xFF;
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
        if (addr < 0xA000) {
            // VRAM
            (_ppu as GameBoyPPU).busWrite(addr, data);
        } else if (addr < 0xD000) {
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
            _joyp = (_joyp & 0x0F) | (data & 0x30);
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
        var cycleCount = 0;
        var startTime = System.getTimer();
        var waitTimeDelta = startTime - _lastTime; 
        while (cycleCount < _mCyclePerCycle) {
            cycleCount += step();
        }
        _lastTime = System.getTimer();

        var exeTimeDelta = _lastTime - startTime;
        var speed = (cycleCount * 1000) / (exeTimeDelta + waitTimeDelta);
        if (!DEBUG_MODE) {
            _mCyclePerCycle += (TARGET_EXEC_TIME_MS - exeTimeDelta) * CYCLE_PER_MS_ADJUST;
        }
        System.println(format("Wait Time: $1$ms | Utilization: $2$% | $3$ MCycle/sec", 
            [waitTimeDelta.format("%d"), ((exeTimeDelta * 100) / (exeTimeDelta + waitTimeDelta)).format("%d"), speed.format("%d")]
        ));
    }

    function cycleMClock(mCycles as Number) as Void {
        (_timer as GameBoyTimer).step(mCycles);
        (_ppu as GameBoyPPU).step(mCycles);
    }

    function initialize(bootRomServer as String, eventCB as Method(Event) as Void) {
        _eventCB = eventCB;
        _bootRomRequest = new ExternalDataRequester(bootRomServer, method(:bootRomReady));
    }

    function initSystem() as Void {
        if (_cpu == null) {
            _bootRomRequest.getData("/boot-rom");
        }
    }

    function insertCart(cart as GameCart?) as Void {
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
}