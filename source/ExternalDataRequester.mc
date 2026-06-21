import Toybox.Lang;
import Toybox.Communications;
import Toybox.StringUtil;

class ExternalDataRequester {
    private var _callBack as Method(ByteArray, String) as Void;
    private var _requestString as String = "";
    private var _inProgress as Boolean = false;
    private var _url as String;

    function onReceive(responseCode as Number, data as String) as Void {
        _inProgress = false;
        if (responseCode == 200) {
            _callBack.invoke(StringUtil.convertEncodedString(data, {:fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64, :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY}), _requestString);
        } else {
            throw new Lang.Exception(); // TODO: Make Custom Exception
        }
    }

    function initialize(url as String, cb as Method(ByteArray, String) as Void) {
        _url = url;
        _callBack = cb;
    }

    function getData(requestString as String) as Void {
        if (_inProgress) {
            throw new Lang.Exception(); // TODO: Make Custom Exception
        }
        _inProgress = true;
        _requestString = requestString;
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        };

        Communications.makeWebRequest(_url + _requestString, null, options, method(:onReceive));
    }
}