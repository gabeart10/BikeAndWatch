import Toybox.Lang;
import Toybox.Communications;
import Toybox.StringUtil;

class RomBankTransaction {
    private var _callBack;
    private var _bank as Number?;

    function onReceive(responseCode as Number, data as String?) as Void {
        if (responseCode == 200) {
            _callBack.invoke(StringUtil.convertEncodedString(data, {:fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64, :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY}), _bank);
        } else {
            throw new Lang.Exception(); // TODO: Make Custom Exception
        }
    }

    function getData(url as String, bank as Number, cb as Method(ByteArray, Number) as Void) as Void {
        _callBack = cb;
        _bank = bank;
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        };

        Communications.makeWebRequest(url + bank.toString(), null, options, method(:onReceive));
    }
}