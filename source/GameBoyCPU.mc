import Toybox.Lang;

class GameBoyCPU {
    private var _bootRom as ByteArray?;
    private var _busRequest as BusRequestFunc;
    private var _pc as Number = 0; // Program Counter
    private var _sp as Number = 0; // Stack Pointer
    private var _a as Number = 0; // Accumulator
    private var _f as Number = 0; // Flags
    private var _bc as Number = 0; // BC Register
    private var _de as Number = 0; // DE Register
    private var _hl as Number = 0; // HL Register

    function initialize(bootRom as ByteArray, busRequest as BusRequestFunc) {
        _bootRom = bootRom;
        _busRequest = busRequest;
    }
}