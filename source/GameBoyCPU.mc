import Toybox.Lang;

class GameBoyCPU {
    private var _bootRom as ByteArray?;
    private var _busRequest as BusRequestFunc;
    private var _pc as Number = 0; // Program Counter
    private var _sp as Number = 0; // Stack Pointer
    private var _a as Number = 0; // Accumulator
    private var _b as Number = 0; // B Register
    private var _c as Number = 0; // C Register
    private var _d as Number = 0; // D Register
    private var _e as Number = 0; // E Register
    private var _h as Number = 0; // H Register
    private var _l as Number = 0; // L Register
    private var _f as Number = 0; // Flags
    private var _ie as Number = 0; // Interrupt Enable Register

    private function cpuBusRequest(addr as Number, data as Number?, isWrite as Boolean) as Number? {
        if (addr == 0xFF50) {
            // BOOT ROM Lock
            if (isWrite && data == 1) {
                _bootRom = null; // Lock the boot ROM
            } else if (!isWrite) {
                return _bootRom != null ? 1 : 0; 
            }
        } else if (_bootRom != null && addr < 0x100 && !isWrite) {
            // During boot, the first 256 bytes of the address space are mapped to the boot ROM
            return _bootRom[addr];
        } else {
            return _busRequest.invoke(addr, data, isWrite);
        }
        return 0;
    }

    function initialize(bootRom as ByteArray, busRequest as BusRequestFunc) {
        _bootRom = bootRom;
        _busRequest = busRequest;
    }

    function bootRomReady() as Boolean {
        return _bootRom != null;
    }

    function step() as Number {
        var mCycles = 1;
        var opcode = cpuBusRequest(_pc, null, false);
        if (opcode == null) {
            // Bus contention
            return mCycles;
        }
        _pc += 1;

        

        return mCycles;
    }
}