import Toybox.Lang;
import Toybox.Application;

module GameCart {
    class Manager {
        typedef ReadyCallback as Method(gc as GameCart) as Void;
        private const HEADER_CART_TYPE as Number = 0x147;
        private const HEADER_ROM_SIZE as Number = 0x148;
        private enum CartType {
            CART_ROM_ONLY = 0x00,
            CART_MBC1 = 0x01
        }

        static private var _manager as Manager?;
        private var _requester as ExternalDataRequester = new ExternalDataRequester(method(:bankReady));
        private var _storedCarts as Array<String>;
        private var _cb as ReadyCallback?;
        private var _inProcess as Boolean = false;
        private var _currRomName as String = "";
        private var _currBank as Number = 0;
        private var _maxBanks as Number = 2;

        private function initialize() {
            var storedCarts = Storage.getValue("stored_carts");
            if (storedCarts == null) {
                _storedCarts = new[0];
                updateStoredCarts();
            } else {
                _storedCarts = storedCarts as Array<String>;
            }
        }

        private function updateStoredCarts() as Void {
            Storage.setValue("stored_carts", _storedCarts as Array<Storage.ValueType>);
        }

        private function createCart(name as String) as GameCart {
            var type;
            {
                // Limit bankZero scope so that it is not kept in memory during the GameCart initialization
                var bankZero = Storage.getValue("cart_" + name + "_bank_0");
                if (bankZero == null) {
                    throw new Lang.Exception();
                }
                type = (bankZero as ByteArray)[HEADER_CART_TYPE];
            }
            switch (type) {
                case CART_ROM_ONLY:
                    return new GameCart(name);
                default:
                    throw new Lang.Exception();
            }      
        } 

        function bankReady(data as ByteArray, requestString as String) as Void {
            if (_currBank == 0) {
                // Store bank 0
                Storage.setValue("cart_" + _currRomName + "_bank_0", data);
                _currBank++;
                _requester.getData(_currRomName + "/1");
                _maxBanks = 1 << (data[HEADER_ROM_SIZE] + 1);
            } else {
                Storage.setValue("cart_" + _currRomName + "_bank_" + _currBank, data);
                _currBank++;
                if (_currBank < _maxBanks) {
                    _requester.getData(_currRomName + "/" + _currBank);
                } else {
                    // All banks have been stored
                    _storedCarts.add(_currRomName);
                    updateStoredCarts();
                    _inProcess = false;
                    if (_cb != null) {
                        _cb.invoke(createCart(_currRomName));
                    }
                }
            }
        }

        static function get() as Manager {
            if (_manager == null) {
                _manager = new Manager();
            }
            return _manager;
        }

        function getCart(romName as String, cb as ReadyCallback) as Void {
            if (_inProcess) {
                throw new Lang.Exception();
            }

            if (_storedCarts.indexOf(romName) != -1) {
                // Cart data is already stored
                cb.invoke(createCart(romName));
                return;
            }
            _inProcess = true;
            _cb = cb;
            _currRomName = romName;
            _currBank = 0;
            _maxBanks = 2;
            _requester.getData(romName + "/0");
        }
    }
}