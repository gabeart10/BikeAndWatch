import Toybox.Lang;

// data is null for read, otherwise it's a write
typedef BusRequestFunc as Method(addr as Number, data as Number?) as Number;

class GameBoy {
    private var _cart as GameCart?;
    private var _cpu as GameBoyCPU?;
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
        } else {
            return 0xFF;
        }
    }

    function initialize(bootRomServer as String) {
        _bootRomRequest = new ExternalDataRequester(bootRomServer, method(:bootRomReady));
        _bootRomRequest.getData("/boot-rom");
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