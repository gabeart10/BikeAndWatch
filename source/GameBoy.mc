import Toybox.Lang;

// data is null for read, otherwise it's a write
typedef GBBusRequestFunc as Method(addr as Number, data as Number?) as Number;

class GameBoy {
    private var _cart as GameCart?;
    private var _cpu as GameBoyCPU?;
    private var _wram as ByteArray = new ByteArray();
    private var _bootRomRequest as ExternalDataRequester;

    function bootRomReady(data as ByteArray, requestString as String) as Void {
        _cpu = new GameBoyCPU(data, method(:busRequest));
        for (var n = 0; n < 100; n++) {
            _cpu.step();
        }
    }

    function busRequest(addr as Number, data as Number?) as Number {
        if (addr < 0x8000 && data == null) {
            // ROM
            if (_cart != null) {
                return _cart.readByte(addr);
            } else {
                return 0xFF; // No cart inserted, return open bus value
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
            return 0xFF;
        } else if (addr == 0xFF00) {
            // Joypad Input
            return 0xFF;
        } else if (addr < 0xFF03) {
            // Serial Transfer
            return 0xFF;
        } else if (addr < 0xFF08) {
            // Timer registers
            return 0xFF;
        } else if (addr < 0xFF40) {
            // Audio
            return 0xFF;
        } else if (addr < 0xFF4C) {
            // LCD
            return 0xFF;
        } else if (addr == 0xFF46) {
            // OAM DMA
            return 0xFF;
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