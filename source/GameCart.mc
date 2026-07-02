import Toybox.Lang;
import Toybox.Application;
 
module GameCart {
    class GameCart {
        protected var _name as String;
        protected var _romData as ByteArray = new[0]b;

        protected function getBank(bankNum as Number) as ByteArray {
            var bankData = Storage.getValue("cart_" + _name + "_bank_" + bankNum);
            if (bankData != null) {
                return bankData as ByteArray;
            } else {
                throw new Lang.Exception();
            }
        } 

        function initialize(name as String) {
            _name = name;
            // Load bank 0 and bank 1 from storage
            _romData.addAll(getBank(0));
            _romData.addAll(getBank(1));
        }

        function busRead(addr as Number) as Number {
            return _romData[addr];
        }

        function busWrite(addr as Number, data as Number) as Void {
        }
    }
}