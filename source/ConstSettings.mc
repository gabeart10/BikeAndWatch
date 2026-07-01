import Toybox.Lang;

const PRINT_TRACE as Boolean = false;

const STEPS_PER_CYCLE as Number = 9000;

const EMU_CYCLE_MS as Number = 100;

// Divider for PPU frame rendering. 1 = render every frame, 2 = render every other frame, etc.
const PPU_FRAME_DIVIDER as Number = 4;