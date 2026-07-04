import Toybox.Lang;
import Toybox.Application;
import Toybox.System;

module GameCart {
    typedef GameCart as interface {
        function busRead(addr as Number) as Number;
        function busWrite(addr as Number, data as Number) as Void;
        function save() as Void;
    };

    function getBank(name as String, bankNum as Number, type as String) as ByteArray {
        var bankData = Storage.getValue("cart_" + name + "_" + type + "_bank_" + bankNum);
        if (bankData != null) {
            return bankData as ByteArray;
        } else {
            System.println("Missing bank " + bankNum + " (" + type + ") for cart " + name);
            throw new Lang.Exception();
        }
    }

    class Manager {
        typedef ReadyCallback as Method(gc as GameCart) as Void;
        private enum CartHeader {
            HEADER_CART_TYPE = 0x147,
            HEADER_ROM_SIZE = 0x148,
        }
        private enum CartType {
            CART_ROM_ONLY = 0x00,
            CART_MBC1 = 0x01,
            CART_MBC1_RAM = 0x02,
            CART_MBC1_RAM_BAT = 0x03,
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

        private function initRam(name as String, bankCnt as Number) as Void {
            for (var i = 0; i < bankCnt; i++) {
                if (Storage.getValue("cart_" + name + "_ram_bank_" + i) == null) {
                    // Initialize RAM banks if they don't exist
                    Storage.setValue("cart_" + name + "_ram_bank_" + i, new[8192]b);
                }
            }
        }


        private function createCart(name as String) as GameCart {
            var type;
            var romBankCnt;
            {
                // Limit bankZero scope so that it is not kept in memory during the GameCart initialization
                var bankZero = (Storage.getValue("cart_" + name + "_rom_bank_0") as ByteArray?);
                if (bankZero == null) {
                    System.println("Missing ROM bank 0 for cart " + name);
                    throw new Lang.Exception();
                }
                type = bankZero[HEADER_CART_TYPE];
                romBankCnt = 1 << (bankZero[HEADER_ROM_SIZE] + 1);
            }
            switch (type) {
                case CART_ROM_ONLY:
                    return new RomOnly(name);
                case CART_MBC1:
                    return new MBC1(name, romBankCnt, 0);
                case CART_MBC1_RAM:
                case CART_MBC1_RAM_BAT:
                    // Always 32KiB of RAM
                    initRam(name, 4);
                    return new MBC1(name, romBankCnt, 4);
                default:
                    System.println("Unsupported cart type: " + type + " for cart " + name);
                    throw new Lang.Exception();
            }      
        } 

        function bankReady(data as ByteArray, requestString as String) as Void {
            if (_currBank == 0) {
                // Store bank 0
                Storage.setValue("cart_" + _currRomName + "_rom_bank_0", data);
                _currBank++;
                _requester.getData(_currRomName + "/1");
                _maxBanks = 1 << (data[HEADER_ROM_SIZE] + 1);
            } else {
                Storage.setValue("cart_" + _currRomName + "_rom_bank_" + _currBank, data);
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
                System.println("Cart load already in progress: " + romName);
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