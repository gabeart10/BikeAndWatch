import Toybox.Lang;
import Toybox.Application;
 
module GameCart {
    class MBC1 extends GameCart {
        private enum BankingMode {
            MODE_SIMPLE = 0,
            MODE_ADVANCED = 1
        }
        private var _ramEnabled as Boolean = false;
        private var _ram as ByteArray = new[0]b;
        private var _ramBankCnt as Number;
        private var _romBankCnt as Number;
        private var _currRomBank as Number = 1;
        private var _currRamBank as Number = 0;
        private var _bankingMode as Number = MODE_SIMPLE;

        function initialize(name as String, romBankCnt as Number, ramBankCnt as Number) {
            GameCart.initialize(name);
            _romBankCnt = romBankCnt;
            _ramBankCnt = ramBankCnt;
            if (_ramBankCnt > 0) {
                _ram = getBank(0, "ram");
            }
        }

        function busWrite(addr as Number, data as Number) as Void {
            if (addr < 0x2000) {
                // RAM enable/disable
                _ramEnabled = (data & 0x0F) == 0x0A;
            } else if (addr < 0x4000) {
                // ROM bank select
                var newBank = data & 0x1F;
                if (newBank == 0) {
                    newBank = 1;
                }
                _currRomBank = (_currRomBank & 0x60) | newBank;

                // Switch to the new ROM bank
                _rom = _rom.slice(0, 0x4000);
                _rom.addAll(getBank(_currRomBank % _romBankCnt, "rom"));
            } else if (addr < 0x6000) {
                // Upper ROM bank bits
                _currRomBank = ((data & 0x03) << 5) | (_currRomBank & 0x1F);

                // RAM bank select or upper ROM bank bits
                if (_romBankCnt >= 64) {
                    // Switch to the new ROM bank(s)
                    if (_bankingMode == MODE_ADVANCED) {
                        _rom = getBank((_currRomBank & 0x60) % _romBankCnt, "rom");
                    } else {
                        _rom = _rom.slice(0, 0x4000);
                    }
                    _rom.addAll(getBank(_currRomBank % _romBankCnt, "rom"));
                } else if (_ramBankCnt > 1 && _bankingMode == MODE_ADVANCED) {
                    // RAM bank select
                    Storage.setValue("cart_" + _name + "_ram_bank_" + _currRamBank, _ram);
                    _currRamBank = data & 0x03;
                    _ram = getBank(_currRamBank % _ramBankCnt, "ram");
                }
            } else if (addr < 0x8000) {
                // Banking mode select
                _bankingMode = data & 0x01;

                // Switch to the new ROM/RAM bank(s)
                if (_bankingMode == MODE_ADVANCED) {
                    if (_ramBankCnt > 1) {
                        _currRamBank = _currRomBank >> 5;
                        _ram = getBank(_currRamBank % _ramBankCnt, "ram");
                    }
                    _rom = getBank((_currRomBank & 0x60) % _romBankCnt, "rom");
                } else {
                    if (_currRamBank != 0) {
                        Storage.setValue("cart_" + _name + "_ram_bank_" + _currRamBank, _ram);
                        _currRamBank = 0;
                        _ram = getBank(_currRamBank, "ram");
                    }
                    _rom = _rom.slice(0, 0x4000);
                }
                _rom.addAll(getBank(_currRomBank % _romBankCnt, "rom"));
            } else if (addr >= 0xA000 && _ramEnabled) {
                // External RAM write
                _ram[addr - 0xA000] = data;
            }
        }
    }
}