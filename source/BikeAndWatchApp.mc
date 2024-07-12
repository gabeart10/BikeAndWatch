import Toybox.Application;
import Toybox.System;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Communications;
import Toybox.StringUtil;

class BikeAndWatchApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onReceive(responseCode as Number, data as String?) as Void {
        if (responseCode == 200) {
            var dataBytes = StringUtil.convertEncodedString(data, {:fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT, :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY});
            System.println(dataBytes.toString());
        } else {
            System.println("Fail");
        }
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
        var url = "https://github.com/gabeart10/BikeAndWatch/raw/main/README.md";

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        };

        Communications.makeWebRequest(url, null, options, method(:onReceive));
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new BikeAndWatchView() ];
    }

}

function getApp() as BikeAndWatchApp {
    return Application.getApp() as BikeAndWatchApp;
}