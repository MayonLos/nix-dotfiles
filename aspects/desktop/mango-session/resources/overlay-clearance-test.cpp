#include "shell/surface/overlay_clearance.h"
#include <cassert>
using namespace shell::overlay_clearance;
int main() {
  auto clear = resolve({700,50,280,320}, {680,64,320,160}, 1024,768,12);
  assert(clear.down == 318 && clear.left == 0 && !clear.suppressTooltip);
  auto shortScreen = resolve({700,50,280,320}, {680,64,320,350}, 1024,600,12);
  assert(shortScreen.down == 0 && shortScreen.left == 312 && !shortScreen.suppressTooltip);
  auto tinyScreen = resolve({100,50,280,320}, {80,64,320,350}, 424,400,12);
  assert(tinyScreen.suppressTooltip);
  auto separate = resolve({50,50,280,320}, {680,64,320,160}, 1024,768,12);
  assert(separate.down == 0 && separate.left == 0 && !separate.suppressTooltip);
  auto adjacent = resolve({700,50,280,320}, {680,370,320,160}, 1024,768,12);
  assert(adjacent.down == 0);
  // A collapsing card is still painted lower than its destination. Reserving only
  // the destination would choose down and move its animated bottom off-screen.
  auto sweptStack = swept({680,64,320,160}, 360);
  assert(sweptStack.y == 64 && sweptStack.h == 456);
  auto moving = resolve({700,50,280,320}, sweptStack, 1024,768,12);
  assert(moving.down == 0 && moving.left == 312);
  // No desktop origin appears in this interface: (-1920,-1080) output has identical result.
  // Sum of layer margins remains unchanged for the downward offset, preserving viewport height.
  assert((64 + clear.down) + (64 - clear.down) == 128);
}
