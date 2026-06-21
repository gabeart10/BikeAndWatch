import Toybox.Lang;

class GameCart {
    private var _serverUrl as String;
    private var _rom as ByteArray?; 
    private var _trans as ExternalDataRequester;
    private var _readyCallback as Method();

    protected function bankReady(data as ByteArray, bank_string as String) as Void {
        // TODO: Clean up with states
        if (_rom == null) {
            // Rom only null on init
            _rom = data;
            _trans.getData("1");
        } else if (_rom.size() < (32 * 1024)) {
            // Local ROM size will only be less than 32kB on init of bank 1
            _rom = _rom.addAll(data);
            // Local ROM is ready
            _readyCallback.invoke();
        } else {
            // TODO
        }
    }

    function initialize(romServer as String, romName as String, readyCallback as Method() as Void) {
        _readyCallback = readyCallback;
        _serverUrl = romServer + "/" + romName + "/";
        _trans = new ExternalDataRequester(_serverUrl, method(:bankReady));

        // Fill local ROM with first two banks of game ROM
        // The max size of local ROM is 2 banks (32kB)
        // The 2nd bank of local ROM will be swaped when needed
        _trans.getData("0");
    }

    function readByte(addr as Number) as Number {
        if (_rom == null || addr >= _rom.size()) {
            throw new Lang.Exception();
        }
        return _rom[addr];
    }
}