import Toybox.Lang;
import Toybox.System;

class GameBoySerial {
    private var _sc as Number = 0;
    private var _sb as Number = 0;
    private var _cycleCnt as Number = 0;
    private var _shiftCnt as Number = 0;
    private var _sendCPUInt as GBCPUSendIntFunc;

    function initialize(sendCPUInt as GBCPUSendIntFunc) {
        _sendCPUInt = sendCPUInt;
    }

    function step(mCycles as Number) as Void {
        _cycleCnt += mCycles;
        if (_cycleCnt >= 128) {
            _cycleCnt -= 128;
            if ((_sc & 0x81) == 0x81) {
                _sb <<= 1;
                _shiftCnt++;
                if (_shiftCnt >= 8) {
                    _shiftCnt = 0;
                    _sc &= 0x7F;
                    _sendCPUInt.invoke(GameBoyCPU.INT_SERIAL);   
                    System.print((_sb >> 8).toChar());
                }
            }
        }
    }

    function busRead(addr as Number) as Number {
        if (addr == 0xFF01) {
            return _sb & 0xFF;
        } else {
            return _sc;
        }
    }

    function busWrite(addr as Number, data as Number) as Void {
        if (addr == 0xFF01) {
            _sb = data;
        } else {
            _sc = data;
        }
    }
}