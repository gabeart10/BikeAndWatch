import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Timer;

// data is null for read, otherwise it's a write
typedef GBBusRequestFunc as Method(addr as Number, data as Number?) as Number;

const START_MCPC as Number = 1000;
const TARGET_EXEC_TIME_MS as Number = 200;
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
    private var _bootRomRequest as ExternalDataRequester;
    private var _eventCB as Method(Event) as Void;
    private var _mainTimer as Timer.Timer = new Timer.Timer();
    private var _lastTime as Number = 0;
    private var _mCyclePerCycle as Number = START_MCPC;

    function bootRomReady(data as ByteArray, requestString as String) as Void {
        _cpu = new GameBoyCPU(data, method(:busRequest));
        _timer = new GameBoyTimer((_cpu as GameBoyCPU).method(:sendInt));
        _ppu = new GameBoyPPU((_cpu as GameBoyCPU).method(:sendInt), method(:ppuFrameDone));
        _eventCB.invoke(EVENT_READY);
    }

    function ppuFrameDone() as Void {
        _eventCB.invoke(EVENT_FRAME_DONE);
    }

    function busRequest(addr as Number, data as Number?) as Number {
        if (addr < 0x8000 && data == null) {
            // ROM
            if (_cart != null) {
                return _cart.readByte(addr);
            }
        } else if (addr < 0xA000) {
            // VRAM
            return 0xFF;
        } else if (addr < 0xC000) {
            // External Ram
            return 0xFF;
        } else if (addr < 0xD000) {
            // WRAM
            if (data == null) {
                return _wram[addr - 0xC000];
            } else {
                _wram[addr - 0xC000] = data;
            }
        } else if (addr < 0xFE00) {
            // Echo WRAM
            if (data == null) {
                return _wram[addr - 0xE000];
            } else {
                _wram[addr - 0xE000] = data;
            }
        } else if (addr < 0xFEA0) {
            // OAM
            return (_ppu as GameBoyPPU).busRequest(addr, data);
        } else if (addr == 0xFF00) {
            // Joypad Input
            return 0xFF;
        } else if (addr < 0xFF03) {
            // Serial Transfer
            return 0xFF;
        } else if (addr < 0xFF08) {
            // Timer registers
            return (_timer as GameBoyTimer).busRequest(addr, data);
        } else if (addr < 0xFF40) {
            // Audio (dummied out by acting as normal ram)
            if (data == null) {
                return _dummyAudio[addr - 0xFF10];
            } else {
                _dummyAudio[addr - 0xFF10] = data;
            }
        } else if (addr < 0xFF4C) {
            // LCD
            return (_ppu as GameBoyPPU).busRequest(addr, data);
        } else if (addr == 0xFF46 && data != null) {
            // OAM DMA
            var src = data << 8;
            for (var dest = 0xFE00; dest < 0xFEA0; dest++) {
                busRequest(dest, busRequest(src, null));
                src++;
            }
        }

        return 0xFF;
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
        _mCyclePerCycle += (TARGET_EXEC_TIME_MS - exeTimeDelta) * CYCLE_PER_MS_ADJUST;
        System.println(format("Wait Time: $1$ms | Utilization: $2$% | $3$ MCycle/sec", 
            [waitTimeDelta.format("%d"), ((exeTimeDelta * 100) / (exeTimeDelta + waitTimeDelta)).format("%d"), speed.format("%d")]
        ));
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

    function step() as Number {
        var mCycles = (_cpu as GameBoyCPU).step();
        (_timer as GameBoyTimer).step(mCycles);
        (_ppu as GameBoyPPU).step(mCycles);
        return mCycles;
    }

    function getFrame() as BufferedBitmap {
        return (_ppu as GameBoyPPU).getBitmap();
    } 
}