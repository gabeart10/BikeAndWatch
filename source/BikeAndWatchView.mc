import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

const SCALE_FACTOR as Float = 2.0;

class BikeAndWatchView extends WatchUi.View {
    private var _gb as GameBoy = new GameBoy(method(:gbEventHandler));
    private var _gcManager as GameCart.Manager = GameCart.Manager.get();
    private var _cart as GameCart.GameCart?;
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
            var transform = new AffineTransform();
            transform.scale(SCALE_FACTOR, SCALE_FACTOR);
            dc.drawBitmap2(80, 50, _gb.getFrame(), {:transform => transform});
            _drawFrame = false;
        }
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
    }

    function cartReady(gc as GameCart.GameCart) as Void {
        _cart = gc;
        _gb.insertCart(_cart);
        _gb.start();
    }

    function gbEventHandler(event as GameBoy.Event) as Void {
        switch (event) {
            case GameBoy.EVENT_READY: {
                _gcManager.getCart(ROM_TO_RUN, method(:cartReady));
            } break;
            
            case GameBoy.EVENT_FRAME_DONE: {
                _drawFrame = true;
                requestUpdate();
            } break;
        }
    }
}
