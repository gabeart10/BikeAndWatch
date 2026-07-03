import Toybox.Lang;
import Toybox.Application;
import Toybox.System;
 
module GameCart {
    class GameCart {
        protected var _name as String;
        protected var _rom as ByteArray = new[0]b;

        protected function getBank(bankNum as Number, type as String) as ByteArray {
            var bankData = Storage.getValue("cart_" + _name + "_" + type + "_bank_" + bankNum);
            if (bankData != null) {
                return bankData as ByteArray;
            } else {
                System.println("Missing bank " + bankNum + " (" + type + ") for cart " + _name);
                throw new Lang.Exception();
            }
        }

        function initialize(name as String) {
            _name = name;
            // Load bank 0 and bank 1 from storage
            _rom.addAll(getBank(0, "rom"));
            _rom.addAll(getBank(1, "rom"));
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