import Toybox.Lang;
import Toybox.Communications;
import Toybox.StringUtil;

class RomBankTransaction {
    private var _callBack as Method(ByteArray, Number) as Void;
    private var _bank as Number = 0;
    private var _inProgress as Boolean = false;
    private var _url as String;

    function onReceive(responseCode as Number, data as String) as Void {
        _inProgress = false;
        if (responseCode == 200) {
            _callBack.invoke(StringUtil.convertEncodedString(data, {:fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64, :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY}), _bank);
        } else {
            throw new Lang.Exception(); // TODO: Make Custom Exception
        }
    }

    function initialize(url as String, cb as Method(ByteArray, Number) as Void) {
        _url = url;
        _callBack = cb;
    }

    function getData(bank as Number) as Void {
        if (_inProgress) {
            throw new Lang.Exception(); // TODO: Make Custom Exception
        }
        _inProgress = true;
        _bank = bank;
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        };

        Communications.makeWebRequest(_url + bank.toString(), null, options, method(:onReceive));
    }
}