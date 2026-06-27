import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

class BikeAndWatchView extends WatchUi.View {
    private var _gb as GameBoy = new GameBoy("http://127.0.0.1:5000", method(:gbEventHandler));
    private var _drawFrame as Boolean = false;

    function initialize() {
        View.initialize();
    }

    // Load your resources here
    function onLayout(dc as Dc) as Void {
        setLayout(Rez.Layouts.MainLayout(dc));
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
        _gb.initSystem();
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        // Call the parent onUpdate function to redraw the layout
        View.onUpdate(dc);
        if (_drawFrame) {
            dc.drawBitmap(0, 50, _gb.getFrame());
            _drawFrame = false;
        }
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
    }

    function gbEventHandler(event as GameBoy.Event) as Void {
        switch (event) {
            case GameBoy.EVENT_READY: {
                _gb.start();
            } break;
            
            case GameBoy.EVENT_FRAME_DONE: {
                _drawFrame = true;
                requestUpdate();
            } break;
        }
    }
}
