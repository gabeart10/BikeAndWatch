import Toybox.Lang;

class GameCart {
    private var _serverUrl as String;
    private var _rom as ByteArray?; 
    private var _trans as RomBankTransaction;
    private var _readyCallback as Method();

    function initialize(rom_server as String, rom_name as String, readyCallback as Method() as Void) {
        _readyCallback = readyCallback;
        _serverUrl = rom_server + "/" + rom_name + "/";
        _trans = new RomBankTransaction(_serverUrl, method(:bankReady));

        // Fill local ROM with first two banks of game ROM
        // The max size of local ROM is 2 banks (32kB)
        // The 2nd bank of local ROM will be swaped when needed
        _trans.getData(0);
    }

    function bankReady(data as ByteArray, bank as Number) as Void {
        // TODO: Clean up with states
        if (_rom == null) {
            // Rom only null on init
            _rom = data;
            _trans.getData(1);
        } else if (_rom.size() < (32 * 1024)) {
            // Local ROM size will only be less than 32kB on init of bank 1
            _rom = _rom.addAll(data);
            // Local ROM is ready
            _readyCallback.invoke();
        } else {
            // TODO
        }
    }

    function readByte(addr as Number) as Number {
        if (_rom == null || addr >= _rom.size()) {
            throw new Lang.Exception();
        }
        return _rom[addr];
    }
}