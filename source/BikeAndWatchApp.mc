import Toybox.Application;
import Toybox.System;
import Toybox.Lang;
import Toybox.WatchUi;

class BikeAndWatchApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function ready() as Void {
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
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