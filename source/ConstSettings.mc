import Toybox.Lang;

const ROM_TO_RUN as String = "Tetris";

const PRINT_TRACE as Boolean = false;
const PRINT_FPS as Boolean = true;

const STEPS_PER_CYCLE as Number = 4000;

const EMU_CYCLE_MS as Number = 50;

// Divider for PPU frame rendering. 1 = render every frame, 2 = render every other frame, etc.
const PPU_FRAME_DIVIDER as Number = 10;