import Toybox.Lang;
import Toybox.Application;
import Toybox.System;
 
module GameCart {
    class RomOnly {
        protected var _name as String;
        protected var _rom as ByteArray = new[0]b;

        function initialize(name as String) {
            _name = name;
            // Load bank 0 and bank 1 from storage
            _rom.addAll(getBank(_name, 0, "rom"));
            _rom.addAll(getBank(_name, 1, "rom"));
        }

        function busRead(addr as Number) as Number {
            return _rom[addr];
        }

        function busWrite(addr as Number, data as Number) as Void {
        }

        function save() as Void {
        }
    }
}