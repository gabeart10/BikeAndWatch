import Toybox.Lang;
import Toybox.Graphics;

class GameBoyPPU {
    private var _sendCPUInt as GBCPUSendIntFunc;
    private var _bitmap as BufferedBitmap;

    function initialize(sendCPUInt as GBCPUSendIntFunc) {
        _sendCPUInt = sendCPUInt;
        var bitmap = Graphics.createBufferedBitmap({
            :width => 144,
            :height => 160
        }).get();

        if (bitmap != null) {
            _bitmap = bitmap as Graphics.BufferedBitmap;
        } else {
            // Failed to create PPU bitmap
            throw new Lang.Exception();
        }
    }

    function getBitmap() as BufferedBitmap {
        return _bitmap;
    }

    function step(mCycles as Number) as Void {

    }
}