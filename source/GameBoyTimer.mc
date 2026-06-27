import Toybox.Lang;

class GameBoyTimer {
    private var _sendCPUInt as GBCPUSendIntFunc;
    private var _systemCounter as Number = 0;
    private var _timerTickCnt as Number = 0;
    private var _tima as Number = 0;
    private var _tma as Number = 0;
    private var _enable as Number = 0;
    private var _clockSelect as Number = 0;
    private var _clockSelectLookup as Array<Number> = [256, 4, 16, 64];

    function initialize(sendCPUInt as GBCPUSendIntFunc) {
        _sendCPUInt = sendCPUInt;
    }

    function step(mCycles as Number) as Void {
        // TODO - Emulate Timer Better
        _systemCounter = (_systemCounter + mCycles) % 0x3FFF;
        if (_enable) {
            var clkSelLim = _clockSelectLookup[_clockSelect];
            _timerTickCnt += mCycles;
            if (_timerTickCnt >= clkSelLim) {
                _tima += _timerTickCnt / clkSelLim;
                _timerTickCnt %= clkSelLim;
                if (_tima > 0xFF) {
                    _sendCPUInt.invoke(GameBoyCPU.INT_TIMER);
                    _tima = _tma + ((_tima - _tma) % (0xFF - _tma));
                }
            }
        }
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
            return (_enable << 2) | _clockSelect;
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
        } else if (addr == 0xFF06) {
            // TMA
            _tma = data;
        } else if (addr == 0xFF07) {
            // TAC
            _clockSelect = data & 0x3;
            _enable = (data >> 2) & 0x1;
        }
    }
}