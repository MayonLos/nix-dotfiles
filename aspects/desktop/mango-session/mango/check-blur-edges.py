#!/usr/bin/env python3
"""Pixel regression for Scenefx's full-size, progressively smaller blur pyramid.

Mesa renders the locked GLSL directly in a surfaceless GLES2 context. The two
full-size FBOs retain poison pixels outside each level's top-left scissor, just
as Scenefx does. `--expect-artifact` is for proving the unpatched shaders fail.
"""
from __future__ import annotations

import argparse
import ctypes as C
import math
from pathlib import Path
import sys

EGL_NONE = 0x3038
EGL_SURFACE_TYPE = 0x3033
EGL_PBUFFER_BIT = 0x0001
EGL_RENDERABLE_TYPE = 0x3040
EGL_OPENGL_ES2_BIT = 0x0004
EGL_RED_SIZE = 0x3024
EGL_GREEN_SIZE = 0x3023
EGL_BLUE_SIZE = 0x3022
EGL_ALPHA_SIZE = 0x3021
EGL_WIDTH = 0x3057
EGL_HEIGHT = 0x3056
EGL_CONTEXT_CLIENT_VERSION = 0x3098
EGL_PLATFORM_SURFACELESS_MESA = 0x31DD
GL_VERTEX_SHADER = 0x8B31
GL_FRAGMENT_SHADER = 0x8B30
GL_COMPILE_STATUS = 0x8B81
GL_LINK_STATUS = 0x8B82
GL_TEXTURE_2D = 0x0DE1
GL_TEXTURE_MIN_FILTER = 0x2801
GL_TEXTURE_MAG_FILTER = 0x2800
GL_TEXTURE_WRAP_S = 0x2802
GL_TEXTURE_WRAP_T = 0x2803
GL_LINEAR = 0x2601
GL_CLAMP_TO_EDGE = 0x812F
GL_RGBA = 0x1908
GL_UNSIGNED_BYTE = 0x1401
GL_FRAMEBUFFER = 0x8D40
GL_COLOR_ATTACHMENT0 = 0x8CE0
GL_FRAMEBUFFER_COMPLETE = 0x8CD5
GL_COLOR_BUFFER_BIT = 0x4000
GL_SCISSOR_TEST = 0x0C11
GL_TEXTURE0 = 0x84C0
GL_FLOAT = 0x1406
GL_TRIANGLE_STRIP = 0x0005


def check(ok: bool, message: str) -> None:
    if not ok:
        raise AssertionError(message)


def load_library(path: str) -> C.CDLL:
    lib = C.CDLL(path)
    lib._path = path
    return lib


def bind(lib: C.CDLL, name: str, restype, argtypes):
    fn = getattr(lib, name)
    fn.restype = restype
    fn.argtypes = argtypes
    return fn


def egl_context(egl: C.CDLL):
    get_platform = getattr(egl, "eglGetPlatformDisplay", None)
    if get_platform is None:
        get_platform = getattr(egl, "eglGetPlatformDisplayEXT", None)
    check(get_platform is not None, "libEGL has no surfaceless display entrypoint")
    get_platform.restype = C.c_void_p
    get_platform.argtypes = [C.c_uint, C.c_void_p, C.POINTER(C.c_int)]
    display = get_platform(EGL_PLATFORM_SURFACELESS_MESA, None, None)
    check(bool(display), "could not get EGL surfaceless display")

    initialize = bind(egl, "eglInitialize", C.c_uint,
                      [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_int)])
    major, minor = C.c_int(), C.c_int()
    check(initialize(display, C.byref(major), C.byref(minor)) != 0,
          "eglInitialize failed; use Mesa with EGL_PLATFORM=surfaceless")
    bind(egl, "eglBindAPI", C.c_uint, [C.c_uint])(0x30A0)  # EGL_OPENGL_ES_API

    attrs = (C.c_int * 17)(
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE,
    )
    config = C.c_void_p()
    count = C.c_int()
    choose = bind(egl, "eglChooseConfig", C.c_uint,
                  [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_void_p),
                   C.c_int, C.POINTER(C.c_int)])
    check(choose(display, attrs, C.byref(config), 1, C.byref(count)) != 0 and count.value,
          "no EGL ES2 pbuffer config")
    pbuffer_attrs = (C.c_int * 5)(EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE)
    surface = bind(egl, "eglCreatePbufferSurface", C.c_void_p,
                   [C.c_void_p, C.c_void_p, C.POINTER(C.c_int)])(
                       display, config, pbuffer_attrs)
    check(bool(surface), "eglCreatePbufferSurface failed")
    context_attrs = (C.c_int * 3)(EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE)
    context = bind(egl, "eglCreateContext", C.c_void_p,
                   [C.c_void_p, C.c_void_p, C.c_void_p, C.POINTER(C.c_int)])(
                       display, config, None, context_attrs)
    check(bool(context), "eglCreateContext failed")
    make_current = bind(egl, "eglMakeCurrent", C.c_uint,
                        [C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p])
    check(make_current(display, surface, surface, context) != 0,
          "eglMakeCurrent failed")
    return display, surface, context


class Renderer:
    def __init__(self, gl: C.CDLL, root: Path):
        self.gl = gl
        self.root = root
        self._bind_gl()
        self.programs = {}
        vertex_source = """
            attribute vec2 pos;
            varying mediump vec2 v_texcoord;
            void main() {
              gl_Position = vec4(pos, 0.0, 1.0);
              v_texcoord = pos * 0.5 + 0.5;
            }
        """
        for level, filename in ((1, "blur1.frag"), (2, "blur2.frag")):
            fragment = (root / "render/fx_renderer/shaders" / filename).read_text()
            self.programs[level] = self._program(vertex_source, fragment)

    def _bind_gl(self):
        gl = self.gl
        bind(gl, "glCreateShader", C.c_uint, [C.c_uint])
        bind(gl, "glShaderSource", None,
             [C.c_uint, C.c_int, C.POINTER(C.c_char_p), C.POINTER(C.c_int)])
        bind(gl, "glCompileShader", None, [C.c_uint])
        bind(gl, "glGetShaderiv", None, [C.c_uint, C.c_uint, C.POINTER(C.c_int)])
        bind(gl, "glGetShaderInfoLog", None,
             [C.c_uint, C.c_int, C.POINTER(C.c_int), C.c_char_p])
        bind(gl, "glCreateProgram", C.c_uint, [])
        bind(gl, "glAttachShader", None, [C.c_uint, C.c_uint])
        bind(gl, "glBindAttribLocation", None, [C.c_uint, C.c_uint, C.c_char_p])
        bind(gl, "glLinkProgram", None, [C.c_uint])
        bind(gl, "glGetProgramiv", None, [C.c_uint, C.c_uint, C.POINTER(C.c_int)])
        bind(gl, "glGetProgramInfoLog", None,
             [C.c_uint, C.c_int, C.POINTER(C.c_int), C.c_char_p])
        bind(gl, "glGetUniformLocation", C.c_int, [C.c_uint, C.c_char_p])
        bind(gl, "glGetAttribLocation", C.c_int, [C.c_uint, C.c_char_p])
        bind(gl, "glGenTextures", None, [C.c_int, C.POINTER(C.c_uint)])
        bind(gl, "glBindTexture", None, [C.c_uint, C.c_uint])
        bind(gl, "glTexParameteri", None, [C.c_uint, C.c_uint, C.c_int])
        bind(gl, "glTexImage2D", None,
             [C.c_uint, C.c_int, C.c_int, C.c_int, C.c_int, C.c_int,
              C.c_uint, C.c_uint, C.c_void_p])
        bind(gl, "glGenFramebuffers", None, [C.c_int, C.POINTER(C.c_uint)])
        bind(gl, "glBindFramebuffer", None, [C.c_uint, C.c_uint])
        bind(gl, "glFramebufferTexture2D", None,
             [C.c_uint, C.c_uint, C.c_uint, C.c_uint, C.c_int])
        bind(gl, "glCheckFramebufferStatus", C.c_uint, [C.c_uint])
        bind(gl, "glViewport", None, [C.c_int, C.c_int, C.c_int, C.c_int])
        bind(gl, "glEnable", None, [C.c_uint])
        bind(gl, "glDisable", None, [C.c_uint])
        bind(gl, "glScissor", None, [C.c_int, C.c_int, C.c_int, C.c_int])
        bind(gl, "glClearColor", None, [C.c_float, C.c_float, C.c_float, C.c_float])
        bind(gl, "glClear", None, [C.c_uint])
        bind(gl, "glUseProgram", None, [C.c_uint])
        bind(gl, "glActiveTexture", None, [C.c_uint])
        bind(gl, "glUniform1i", None, [C.c_int, C.c_int])
        bind(gl, "glUniform1f", None, [C.c_int, C.c_float])
        bind(gl, "glUniform2f", None,
             [C.c_int, C.c_float, C.c_float])
        bind(gl, "glUniform4f", None,
             [C.c_int, C.c_float, C.c_float, C.c_float, C.c_float])
        bind(gl, "glEnableVertexAttribArray", None, [C.c_uint])
        bind(gl, "glVertexAttribPointer", None,
             [C.c_uint, C.c_int, C.c_uint, C.c_ubyte, C.c_int, C.c_void_p])
        bind(gl, "glDrawArrays", None, [C.c_uint, C.c_int, C.c_int])
        bind(gl, "glReadPixels", None,
             [C.c_int, C.c_int, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_void_p])
        bind(gl, "glFinish", None, [])
        bind(gl, "glGetString", C.c_char_p, [C.c_uint])

    def _shader(self, kind: int, source: str) -> int:
        gl = self.gl
        shader = gl.glCreateShader(kind)
        data = C.c_char_p(source.encode())
        gl.glShaderSource(shader, 1, C.byref(data), None)
        gl.glCompileShader(shader)
        status = C.c_int()
        gl.glGetShaderiv(shader, GL_COMPILE_STATUS, C.byref(status))
        if not status.value:
            log = C.create_string_buffer(8192)
            length = C.c_int()
            gl.glGetShaderInfoLog(shader, len(log), C.byref(length), log)
            raise RuntimeError(log.value.decode(errors="replace"))
        return shader

    def _program(self, vertex: str, fragment: str):
        gl = self.gl
        vs = self._shader(GL_VERTEX_SHADER, vertex)
        fs = self._shader(GL_FRAGMENT_SHADER, fragment)
        program = gl.glCreateProgram()
        gl.glAttachShader(program, vs)
        gl.glAttachShader(program, fs)
        gl.glBindAttribLocation(program, 0, b"pos")
        gl.glLinkProgram(program)
        status = C.c_int()
        gl.glGetProgramiv(program, GL_LINK_STATUS, C.byref(status))
        if not status.value:
            log = C.create_string_buffer(8192)
            length = C.c_int()
            gl.glGetProgramInfoLog(program, len(log), C.byref(length), log)
            raise RuntimeError(log.value.decode(errors="replace"))
        return program

    def _texture(self, width: int, height: int, pixels=None) -> tuple[int, int]:
        gl = self.gl
        texture, framebuffer = C.c_uint(), C.c_uint()
        gl.glGenTextures(1, C.byref(texture))
        gl.glBindTexture(GL_TEXTURE_2D, texture.value)
        gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        pointer = C.cast(pixels, C.c_void_p) if pixels is not None else None
        gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
                        GL_RGBA, GL_UNSIGNED_BYTE, pointer)
        gl.glGenFramebuffers(1, C.byref(framebuffer))
        gl.glBindFramebuffer(GL_FRAMEBUFFER, framebuffer.value)
        gl.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                  GL_TEXTURE_2D, texture.value, 0)
        check(gl.glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE,
              "incomplete GLES framebuffer")
        return texture.value, framebuffer.value

    def render(self, width: int, height: int):
        gl = self.gl
        source = bytearray(width * height * 4)
        for y in range(height):
            for x in range(width):
                i = (y * width + x) * 4
                # The four wide borders are uniform charcoal. A bright center
                # and a high-contrast checker exercise blur strength and leak.
                bright = 0
                if width // 3 < x < 2 * width // 3 and height // 3 < y < 2 * height // 3:
                    bright = 220 if ((x // 10 + y // 10) & 1) else 72
                source[i:i + 4] = bytes((18 + bright, 20 + bright, 22 + bright, 255))
        source_arr = (C.c_ubyte * len(source)).from_buffer(source)
        src_tex, _ = self._texture(width, height, source_arr)

        # Deliberately different stale values expose sampling outside a level.
        poison_a = (C.c_float * 4)(1.0, 0.1, 0.7, 1.0)
        poison_b = (C.c_float * 4)(1.0, 0.9, 0.1, 1.0)
        a_tex, a_fb = self._texture(width, height)
        b_tex, b_fb = self._texture(width, height)
        gl.glViewport(0, 0, width, height)
        for fb, poison in ((a_fb, poison_a), (b_fb, poison_b)):
            gl.glBindFramebuffer(GL_FRAMEBUFFER, fb)
            gl.glClearColor(*poison)
            gl.glClear(GL_COLOR_BUFFER_BIT)

        vertices = (C.c_float * 8)(-1, -1, 1, -1, -1, 1, 1, 1)
        gl.glEnable(GL_SCISSOR_TEST)
        sequence = ((1, 0, 1, a_fb), (1, 1, 2, b_fb),
                    (2, 2, 1, a_fb), (2, 1, 0, b_fb))
        for shader_kind, source_level, destination_level, target_fb in sequence:
            program = self.programs[shader_kind]
            gl.glBindFramebuffer(GL_FRAMEBUFFER, target_fb)
            gl.glViewport(0, 0, width, height)
            divisor = 1 << destination_level
            source_divisor = 1 << source_level
            region_w = (width + divisor - 1) // divisor
            region_h = (height + divisor - 1) // divisor
            gl.glScissor(0, 0, region_w, region_h)
            gl.glUseProgram(program)
            gl.glActiveTexture(GL_TEXTURE0)
            input_tex = src_tex if shader_kind == 1 and source_level == 0 else (
                a_tex if (shader_kind == 1 or source_level == 2) else b_tex)
            # Up pass 2 reads level-2 B, while down pass 2 reads downsampled A.
            if shader_kind == 2 and source_level == 2:
                input_tex = b_tex
            elif shader_kind == 2 and source_level == 1:
                input_tex = a_tex
            gl.glBindTexture(GL_TEXTURE_2D, input_tex)
            gl.glUniform1i(gl.glGetUniformLocation(program, b"tex"), 0)
            gl.glUniform1f(gl.glGetUniformLocation(program, b"radius"), 5.0)
            halfpixel = gl.glGetUniformLocation(program, b"halfpixel")
            if shader_kind == 1:
                gl.glUniform2f(halfpixel, 1.0 / width, 1.0 / height)
            else:
                gl.glUniform2f(halfpixel, 0.25 / width, 0.25 / height)
            bounds_loc = gl.glGetUniformLocation(program, b"sample_bounds")
            if bounds_loc >= 0:
                max_u = (math.ceil(width / source_divisor) - 0.5) / width
                max_v = (math.ceil(height / source_divisor) - 0.5) / height
                gl.glUniform4f(bounds_loc, 0.5 / width, 0.5 / height, max_u, max_v)
            gl.glEnableVertexAttribArray(0)
            gl.glVertexAttribPointer(0, 2, GL_FLOAT, 0, 0, C.cast(vertices, C.c_void_p))
            gl.glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

        gl.glDisable(GL_SCISSOR_TEST)
        gl.glFinish()
        result = (C.c_ubyte * (width * height * 4))()
        gl.glBindFramebuffer(GL_FRAMEBUFFER, b_fb)
        gl.glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, result)
        return bytes(result)


def verify(image: bytes, width: int, height: int, expect_artifact: bool):
    # Compare each edge strip against a safe inner point in the same dark
    # wallpaper margin. This catches stale pyramid pixels on every side.
    errors = []
    for axis in ("left", "right", "top", "bottom"):
        diffs = []
        for k in range(4):
            for i in range(64, 128):
                if axis in ("left", "right"):
                    x1 = k if axis == "left" else width - 1 - k
                    x2, y = width // 4, i
                    p1, p2 = (y * width + x1) * 4, (y * width + x2) * 4
                else:
                    y1 = k if axis == "top" else height - 1 - k
                    y2, x = height // 4, i
                    p1, p2 = (y1 * width + x) * 4, (y2 * width + x) * 4
                diffs.append(max(abs(image[p1 + c] - image[p2 + c]) for c in range(3)))
        errors.append((axis, max(diffs, default=0)))
    worst = max((v for _, v in errors), default=0)
    dark_colors = []
    for axis in ("left", "right", "top", "bottom"):
        for k in range(4):
            for i in range(64, 128):
                if axis in ("left", "right"):
                    x, y = k if axis == "left" else width - 1 - k, i
                else:
                    x, y = i, k if axis == "top" else height - 1 - k
                offset = (y * width + x) * 4
                dark_colors.append(tuple(image[offset + c] for c in range(3)))
    dark_delta = max(abs(pixel[c] - (18, 20, 22)[c])
                     for pixel in dark_colors for c in range(3))

    # Ensure blur actually changes the high-frequency central checker.
    checker = []
    for y in range(height // 2 - 20, height // 2 + 20, 2):
        for x in range(width // 2 - 20, width // 2 + 20, 2):
            i = (y * width + x) * 4
            checker.append(image[i])
    mean = sum(checker) / len(checker)
    variance = sum((x - mean) ** 2 for x in checker) / len(checker)
    print(f"{width}x{height}: edge max RGB delta={worst} ({errors}), dark-edge delta={dark_delta}, center variance={variance:.1f}")
    if expect_artifact:
        check(worst > 3 or dark_delta > 3,
              "original shader unexpectedly passed; poison-region artifact not reproduced")
    else:
        check(worst <= 3, f"edge contamination exceeds threshold: {errors}")
        check(dark_delta <= 3, f"edge color departed from dark wallpaper: delta={dark_delta}")
        check(0 < variance < 4000,
              f"blur appears disabled, black, or too weak (variance={variance:.1f})")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--egl", required=True, help="path to libEGL.so.1")
    parser.add_argument("--gles", required=True, help="path to libGLESv2.so.2")
    parser.add_argument("--source", required=True, type=Path, help="Scenefx source root")
    parser.add_argument("--expect-artifact", action="store_true",
                        help="assert unlocked/original blur shaders show the poison leak")
    args = parser.parse_args()
    egl = load_library(args.egl)
    gl = load_library(args.gles)
    egl_context(egl)
    renderer = Renderer(gl, args.source)
    print("GLES renderer:", gl.glGetString(0x1F01).decode())
    for width, height in ((2560, 1600), (2559, 1599)):
        verify(renderer.render(width, height), width, height, args.expect_artifact)
    print("PASS")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise
