import Toybox.Lang;

typedef BusRequestFunc as Method(addr as Number, data as Number?, isWrite as Boolean) as Number?;

class GameBoy {
    private var _cart as GameCart?;
    private var _cpu as GameBoyCPU?;
    private var _bootRomRequest as ExternalDataRequester;

    private function bootRomReady(data as ByteArray, requestString as String) as Void {
        _cpu = new GameBoyCPU(data, method(:busRequest));
    }

    private function busRequest(addr as Number, data as Number?, isWrite as Boolean) as Number? {
        if (addr < 0x8000 && isWrite == false) {
            // ROM
            if (_cart != null) {
                return _cart.readWord(addr);
            } else {
                return 0xFFFF; // No cart inserted, return open bus value
            }
        } else {
            throw new Lang.Exception(); // TODO: Make Custom Exception
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