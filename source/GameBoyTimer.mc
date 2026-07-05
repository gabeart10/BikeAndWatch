import Toybox.Lang;

class GameBoyTimer {
    private const _clockSelectMaskLookup as Array<Number> = [0x0080, 0x0002, 0x0008, 0x0020];
    private var _sendCPUInt as GBCPUSendIntFunc;
    private var _systemCounter as Number = 0x2AC0;
    private var _tima as Number = 0;
    private var _tma as Number = 0;
    private var _enable as Number = 0;
    private var _clockSelect as Number = 0;
    private var _clockSelectMask as Number = _clockSelectMaskLookup[0];
    private var _prevTimerState as Number = 0;
    private var _overflowBuffered as Boolean = false;

    function initialize(sendCPUInt as GBCPUSendIntFunc) {
        _sendCPUInt = sendCPUInt;
    }

    function step() as Void {
        // Using CGB configuration
        // TODO check if emulating DMG or CGB config is faster 
        _systemCounter = (_systemCounter + 1) & 0x3FFF;

        if (_overflowBuffered) {
            _tima = _tma;
            _sendCPUInt.invoke(GameBoyCPU.INT_TIMER); 
            _overflowBuffered = false;
        } else {
            if (_enable) {
                if (((_systemCounter & _clockSelectMask) == 0) && (_prevTimerState != 0)) {
                    // Falling edge detected do timer tick
                    _tima++;
                    if (_tima > 0xFF) {
                        _tima = 0;
                        _overflowBuffered = true;
                    }
                }
            }
        }
        _prevTimerState = _systemCounter & _clockSelectMask;
    }

    function busRead(addr as Number) as Number {
        if (addr == 0xFF04) {
            // DIV
            return _systemCounter >> 6;
        } else if (addr == 0xFF05) {
            // TIMA
            return _tima;
        } else if (addr == 0xFF06) {
            // TMA
            return _tma;
        } else if (addr == 0xFF07) {
            // TAC
            return 0xF8 | (_enable << 2) | _clockSelect;
        }
        return 0xFF;
    }

    function busWrite(addr as Number, data as Number) as Void {
        if (addr == 0xFF04) {
            // DIV
            _systemCounter = 0;
        } else if (addr == 0xFF05) {
            // TIMA
            _tima = data;
            _overflowBuffered = false;
        } else if (addr == 0xFF06) {
            // TMA
            _tma = data;
        } else if (addr == 0xFF07) {
            // TAC
            _clockSelect = data & 0x3;
            _clockSelectMask = _clockSelectMaskLookup[_clockSelect];
            _enable = (data >> 2) & 0x1;
        }
    }
}