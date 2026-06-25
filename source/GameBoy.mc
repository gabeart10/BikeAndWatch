import Toybox.Lang;

// data is null for read, otherwise it's a write
typedef GBBusRequestFunc as Method(addr as Number, data as Number?) as Number;

class GameBoy {
    private var _cart as GameCart?;
    private var _cpu as GameBoyCPU?;
    private var _timer as GameBoyTimer?;
    private var _ppu as GameBoyPPU?;
    private var _wram as ByteArray = new ByteArray();
    private var _dummyAudio as ByteArray = new ByteArray();
    private var _bootRomRequest as ExternalDataRequester;

    function bootRomReady(data as ByteArray, requestString as String) as Void {
        _cpu = new GameBoyCPU(data, method(:busRequest));
        _timer = new GameBoyTimer((_cpu as GameBoyCPU).method(:sendInt));
        _ppu = new GameBoyPPU((_cpu as GameBoyCPU).method(:sendInt));
        for (var n = 0; n < 100; n++) {
            (_cpu as GameBoyCPU).step();
        }
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

    function initialize(bootRomServer as String) {
        _bootRomRequest = new ExternalDataRequester(bootRomServer, method(:bootRomReady));
        _bootRomRequest.getData("/boot-rom");

        // Fill WRAM
        for (var i = 0; i < 4096; i++) {
            _wram.add(0);
        }

        // Fill Dummy Audio
        for (var i = 0; i < 22; i++) {
            _dummyAudio.add(0);
        }
    }

    function insertCart(cart as GameCart?) as Void {
        _cart = cart;
    }

    function switchOn() as Void {
        if (_cpu == null) {
            throw new Lang.Exception(); // TODO: Make Custom Exception
        }

    }
}