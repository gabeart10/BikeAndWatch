import Toybox.Application;
import Toybox.System;
import Toybox.Lang;
import Toybox.WatchUi;

class BikeAndWatchApp extends Application.AppBase {
    var gb as GameBoy?;
    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
        gb = new GameBoy("http://127.0.0.1:5000");
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