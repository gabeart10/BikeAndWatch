import Toybox.Application;
import Toybox.System;
import Toybox.Lang;
import Toybox.WatchUi;

class BikeAndWatchApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    var test;

    function ready() as Void {
        for (var i = 0x0104; i < 0x0133; i++) {
            System.print(test.readByte(i).format("%02X") + " ");
        }
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
        var url = "http://127.0.0.1:5000";
        test = new GameCart(url, "Tetris", method(:ready));
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