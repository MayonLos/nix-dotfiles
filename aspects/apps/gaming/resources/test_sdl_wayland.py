"""Exercise LWJGL's shipped SDL3 with the Prism wrapper's library search path."""
import ctypes
import os

sdl = ctypes.CDLL(os.environ["SDL3_LIBRARY"])
sdl.SDL_Init.argtypes = [ctypes.c_uint32]
sdl.SDL_Init.restype = ctypes.c_bool
sdl.SDL_GetError.restype = ctypes.c_char_p
sdl.SDL_GetCurrentVideoDriver.restype = ctypes.c_char_p
sdl.SDL_CreateWindow.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_uint64]
sdl.SDL_CreateWindow.restype = ctypes.c_void_p
sdl.SDL_DestroyWindow.argtypes = [ctypes.c_void_p]
sdl.SDL_DestroyWindow.restype = None
sdl.SDL_Quit.restype = None
assert sdl.SDL_Init(0x20), sdl.SDL_GetError()
assert sdl.SDL_GetCurrentVideoDriver() == b"wayland"
window = sdl.SDL_CreateWindow(b"Prism SDL3 runtime check", 480, 320, 0)
assert window, sdl.SDL_GetError()
sdl.SDL_DestroyWindow(window)
sdl.SDL_Quit()
print("PASS: LWJGL SDL3 initialized Wayland and created a window inside the Prism wrapper")
