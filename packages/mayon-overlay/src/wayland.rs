//! Wayland layer-shell host: registry, shared-memory buffers, seat input and
//! the main event loop (Wayland socket + control socket multiplexed with
//! `poll(2)`).
//!
//! Design constraints that shaped this file:
//!
//! * The overlay must be a `zwlr_layer_shell_v1` surface on the focused output
//!   with exclusive keyboard, so Super+V/Super+A behave like a modal UI without
//!   stealing a toplevel slot.
//! * Rendering is CPU-side into `wl_shm` XRGB8888 buffers. No EGL/Vulkan/GTK:
//!   the same binary has to run under the pixman renderer in the headless test.
//! * The control socket is part of the same `poll` loop instead of a second
//!   thread, so IPC commands are serialised with input events.

use std::io::Read;
use std::os::fd::{AsFd, AsRawFd, FromRawFd, OwnedFd};
use std::path::PathBuf;
use std::time::{Duration, Instant};

use wayland_client::protocol::{
    wl_buffer, wl_compositor, wl_keyboard, wl_output, wl_pointer, wl_registry, wl_seat, wl_shm,
    wl_region, wl_shm_pool, wl_surface,
};
use wayland_client::{Connection, Dispatch, EventQueue, QueueHandle, WEnum};
use wayland_protocols_wlr::layer_shell::v1::client::{
    zwlr_layer_shell_v1, zwlr_layer_surface_v1,
};
use xkbcommon::xkb;

use crate::ipc::IpcServer;
use crate::logger::{json_string, Logger};
use crate::overlay::{ExitAction, Key, Overlay};

const DEFAULT_WIDTH: u32 = 1280;
const DEFAULT_HEIGHT: u32 = 800;

#[derive(Default)]
struct Globals {
    compositor: Option<wl_compositor::WlCompositor>,
    shm: Option<wl_shm::WlShm>,
    seat: Option<wl_seat::WlSeat>,
    output: Option<wl_output::WlOutput>,
    layer_shell: Option<zwlr_layer_shell_v1::ZwlrLayerShellV1>,
    /// Integer buffer scale taken from the first wl_output. Mango reports the
    /// ceiling of a fractional scale here, which is what an integer
    /// `set_buffer_scale` needs.
    output_scale: i32,
    output_name: Option<String>,
}

struct LayerSurface {
    surface: wl_surface::WlSurface,
    layer_surface: zwlr_layer_surface_v1::ZwlrLayerSurfaceV1,
}

struct KeyboardState {
    keyboard: wl_keyboard::WlKeyboard,
    context: xkb::Context,
    keymap: Option<xkb::Keymap>,
    state: Option<xkb::State>,
}

struct BufferSlot {
    buffer: wl_buffer::WlBuffer,
    ptr: *mut u8,
    len: usize,
    width: u32,
    height: u32,
    busy: bool,
}

impl Drop for BufferSlot {
    fn drop(&mut self) {
        unsafe {
            libc::munmap(self.ptr as *mut libc::c_void, self.len);
        }
    }
}

pub struct WaylandHost {
    pub overlay: Overlay,
    pub logger: Logger,
    pub ipc: Option<IpcServer>,
    pub ready_file: Option<PathBuf>,
    pub socket_path: PathBuf,
    globals: Globals,
    layer: Option<LayerSurface>,
    keyboard: Option<KeyboardState>,
    pointer: Option<wl_pointer::WlPointer>,
    pointer_position: (f32, f32),
    buffers: Vec<BufferSlot>,
    configured: bool,
    width_px: u32,
    height_px: u32,
    scale: f32,
    need_redraw: bool,
    exit: Option<ExitAction>,
    ready_written: bool,
    started: Instant,
}

impl WaylandHost {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        overlay: Overlay,
        logger: Logger,
        ipc: Option<IpcServer>,
        ready_file: Option<PathBuf>,
        socket_path: PathBuf,
    ) -> WaylandHost {
        WaylandHost {
            overlay,
            logger,
            ipc,
            ready_file,
            socket_path,
            globals: Globals::default(),
            layer: None,
            keyboard: None,
            pointer: None,
            pointer_position: (0.0, 0.0),
            buffers: Vec::new(),
            configured: false,
            width_px: DEFAULT_WIDTH,
            height_px: DEFAULT_HEIGHT,
            scale: 1.0,
            need_redraw: true,
            exit: None,
            ready_written: false,
            started: Instant::now(),
        }
    }

    /// Override the integer buffer scale (used by tests and unusual outputs
    /// where wl_output's advertised scale is not the value we want).
    pub fn force_scale(&mut self, scale: i32) {
        self.globals.output_scale = scale.max(1);
    }

    pub fn run(mut self) -> Result<Option<ExitAction>, String> {
        let conn = Connection::connect_to_env()
            .map_err(|err| format!("cannot connect to the Wayland compositor: {}", err))?;
        let mut queue: EventQueue<WaylandHost> = conn.new_event_queue();
        let qh = queue.handle();
        let display = conn.display();
        let _registry = display.get_registry(&qh, ());
        self.logger.event(
            "start",
            &[
                ("mode", json_string(self.overlay.mode.name())),
                ("socket", json_string(&self.socket_path.to_string_lossy())),
            ],
        );
        queue
            .roundtrip(&mut self)
            .map_err(|err| format!("registry roundtrip failed: {}", err))?;
        if self.globals.compositor.is_none()
            || self.globals.shm.is_none()
            || self.globals.layer_shell.is_none()
        {
            return Err("compositor is missing wl_compositor, wl_shm or zwlr_layer_shell_v1".into());
        }
        self.scale = self.globals.output_scale.max(1) as f32;
        self.create_layer(&qh)?;
        queue
            .roundtrip(&mut self)
            .map_err(|err| format!("layer-shell configure roundtrip failed: {}", err))?;

        // Wait for the first configure with a bounded loop: a compositor that
        // never configures the layer surface must not hang the key binding.
        let deadline = Instant::now() + Duration::from_secs(10);
        while !self.configured && self.exit.is_none() {
            if Instant::now() > deadline {
                return Err("timed out waiting for the layer-shell configure event".into());
            }
            conn.flush()
                .map_err(|err| format!("Wayland flush failed: {}", err))?;
            if let Some(guard) = conn.prepare_read() {
                let _ = guard.read();
            }
            queue
                .dispatch_pending(&mut self)
                .map_err(|err| format!("Wayland dispatch failed: {}", err))?;
        }
        if self.configured {
            self.redraw(&qh)?;
        }

        let listener_fd = self.ipc.as_ref().map(|ipc| ipc.listener_fd());
        let mut last_redraw = self.started;
        loop {
            if let Some(exit) = self.exit.take() {
                self.teardown(&conn);
                self.logger.event(
                    "exit",
                    &[
                        ("mode", json_string(self.overlay.mode.name())),
                        ("elapsed_ms", last_redraw.elapsed().as_millis().to_string()),
                    ],
                );
                let _ = conn.flush();
                return Ok(Some(exit));
            }
            conn.flush()
                .map_err(|err| format!("Wayland flush failed: {}", err))?;
            let guard = conn.prepare_read();
            let wayland_fd = conn.backend().poll_fd().as_raw_fd();
            let mut pollfds = [
                libc::pollfd {
                    fd: wayland_fd,
                    events: libc::POLLIN,
                    revents: 0,
                },
                libc::pollfd {
                    fd: listener_fd.unwrap_or(-1),
                    events: libc::POLLIN,
                    revents: 0,
                },
            ];
            let nfds = if listener_fd.is_some() { 2 } else { 1 };
            let timeout = if self.need_redraw { 0 } else { -1 };
            let ready = unsafe { libc::poll(pollfds.as_mut_ptr(), nfds, timeout) };
            if ready < 0 {
                let errno = std::io::Error::last_os_error();
                if errno.raw_os_error() == Some(libc::EINTR) {
                    continue;
                }
                return Err(format!("poll failed: {}", errno));
            }
            let wayland_ready = ready > 0 && pollfds[0].revents != 0;
            if wayland_ready {
                if let Some(guard) = guard {
                    let _ = guard.read();
                }
            } else {
                drop(guard);
            }
            queue
                .dispatch_pending(&mut self)
                .map_err(|err| format!("Wayland dispatch failed: {}", err))?;
            if ready > 0 && nfds > 1 && pollfds[1].revents != 0 {
                self.drain_ipc();
            }
            if self.need_redraw {
                self.redraw(&qh)?;
                last_redraw = Instant::now();
            }
        }
    }

    fn create_layer(&mut self, qh: &QueueHandle<WaylandHost>) -> Result<(), String> {
        let compositor = self.globals.compositor.as_ref().ok_or("no wl_compositor")?;
        let layer_shell = self.globals.layer_shell.as_ref().ok_or("no layer shell")?;
        let surface = compositor.create_surface(qh, ());
        let layer_surface = layer_shell.get_layer_surface(
            &surface,
            None,
            zwlr_layer_shell_v1::Layer::Overlay,
            "mayon-overlay".to_string(),
            qh,
            (),
        );
        layer_surface.set_anchor(
            zwlr_layer_surface_v1::Anchor::Top
                | zwlr_layer_surface_v1::Anchor::Bottom
                | zwlr_layer_surface_v1::Anchor::Left
                | zwlr_layer_surface_v1::Anchor::Right,
        );
        layer_surface.set_exclusive_zone(0);
        layer_surface.set_keyboard_interactivity(
            zwlr_layer_surface_v1::KeyboardInteractivity::Exclusive,
        );
        layer_surface.set_size(0, 0);
        surface.set_buffer_scale(self.scale.max(1.0) as i32);
        surface.commit();
        self.layer = Some(LayerSurface {
            surface,
            layer_surface,
        });
        Ok(())
    }

    fn teardown(&mut self, conn: &Connection) {
        if let Some(layer) = self.layer.take() {
            layer.layer_surface.destroy();
            layer.surface.destroy();
        }
        if let Some(keyboard) = self.keyboard.take() {
            keyboard.keyboard.release();
        }
        if let Some(pointer) = self.pointer.take() {
            pointer.release();
        }
        let _ = conn.flush();
    }

    fn drain_ipc(&mut self) {
        loop {
            let Some(ipc) = &self.ipc else {
                return;
            };
            let stream = match ipc.accept() {
                Ok(Some(stream)) => stream,
                Ok(None) => break,
                Err(error) => {
                    self.logger
                        .event("ipc_error", &[("error", json_string(&error))]);
                    break;
                }
            };
            let overlay = &mut self.overlay;
            let exit = std::cell::RefCell::new(None);
            let result = ipc.serve(stream, |request| {
                let (reply, action) = overlay.ipc_command(request);
                if let Some(action) = action {
                    *exit.borrow_mut() = Some(action);
                }
                reply
            });
            if let Err(error) = result {
                self.logger
                    .event("ipc_error", &[("error", json_string(&error))]);
            }
            if let Some(action) = exit.into_inner() {
                self.exit = Some(action);
            }
            self.need_redraw = true;
        }
    }

    fn mark_buffer_released(&mut self, index: usize) {
        if let Some(slot) = self.buffers.get_mut(index) {
            slot.busy = false;
        }
    }

    /// Create (or reuse) an mmapped shared-memory buffer of the requested size.
    fn acquire_buffer(
        &mut self,
        qh: &QueueHandle<WaylandHost>,
        width: u32,
        height: u32,
    ) -> Result<usize, String> {
        if let Some(index) = self
            .buffers
            .iter()
            .position(|slot| !slot.busy && slot.width == width && slot.height == height)
        {
            self.buffers[index].busy = true;
            return Ok(index);
        }
        if self.buffers.len() > 6 {
            // Drop the oldest idle buffer to bound memory if a compositor never
            // sends release events for destroyed surfaces.
            if let Some(index) = self.buffers.iter().position(|slot| !slot.busy) {
                self.buffers.remove(index);
            }
        }
        let stride = width as usize * 4;
        let len = stride * height as usize;
        let shm = self.globals.shm.as_ref().ok_or("no wl_shm")?;
        let fd = create_memfd("mayon-overlay", len)?;
        let ptr = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                len,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                fd.as_raw_fd(),
                0,
            )
        };
        if ptr == libc::MAP_FAILED {
            return Err(format!(
                "mmap failed: {}",
                std::io::Error::last_os_error()
            ));
        }
        let ptr = ptr as *mut u8;
        let pool = shm.create_pool(fd.as_fd(), len as i32, qh, ());
        let index = self.buffers.len();
        let buffer = pool.create_buffer(
            0,
            width as i32,
            height as i32,
            stride as i32,
            wl_shm::Format::Xrgb8888,
            qh,
            index,
        );
        pool.destroy();
        self.buffers.push(BufferSlot {
            buffer,
            ptr,
            len,
            width,
            height,
            busy: true,
        });
        Ok(index)
    }

    fn redraw(&mut self, qh: &QueueHandle<WaylandHost>) -> Result<(), String> {
        if !self.configured {
            return Ok(());
        }
        let width_px = self.width_px;
        let height_px = self.height_px;
        let scale = self.scale;
        self.overlay.draw(width_px, height_px, scale);
        let pixels = match &self.overlay.canvas {
            Some(canvas) => canvas.to_xrgb8888(),
            None => return Ok(()),
        };
        let index = match self.acquire_buffer(qh, width_px, height_px) {
            Ok(index) => index,
            Err(error) => {
                self.logger
                    .event("render_error", &[("error", json_string(&error))]);
                return Err(error);
            }
        };
        {
            let slot = &mut self.buffers[index];
            unsafe {
                std::ptr::copy_nonoverlapping(pixels.as_ptr(), slot.ptr, slot.len.min(pixels.len()));
            }
            slot.busy = true;
        }
        let Some(layer) = &self.layer else {
            return Ok(());
        };
        layer
            .surface
            .attach(Some(&self.buffers[index].buffer), 0, 0);
        layer
            .surface
            .damage_buffer(0, 0, width_px as i32, height_px as i32);
        layer.surface.commit();
        self.need_redraw = false;
        self.overlay.log_ready();
        if !self.ready_written {
            if let Some(path) = &self.ready_file {
                let layout = self.overlay.layout.as_ref();
                let payload = format!(
                    "{{\"mode\":{},\"width_px\":{},\"height_px\":{},\"scale\":{},\"card\":{}}}\n",
                    json_string(self.overlay.mode.name()),
                    width_px,
                    height_px,
                    scale,
                    match layout {
                        Some(layout) => format!(
                            "{{\"x\":{:.1},\"y\":{:.1},\"w\":{:.1},\"h\":{:.1}}}",
                            layout.card_x, layout.card_y, layout.card_w, layout.card_h
                        ),
                        None => "null".to_string(),
                    }
                );
                let _ = std::fs::write(path, payload);
            }
            self.ready_written = true;
        }
        Ok(())
    }

    fn handle_key(&mut self, key: u32, pressed: bool) {
        if !pressed {
            return;
        }
        let Some(keyboard) = &mut self.keyboard else {
            return;
        };
        let Some(state) = &mut keyboard.state else {
            return;
        };
        let keycode = key + 8;
        state.update_key(keycode.into(), xkb::KeyDirection::Down);
        let symbol = state.key_get_one_sym(keycode.into());
        let utf8 = state.key_get_utf8(keycode.into());
        let ctrl = state.mod_name_is_active(xkb::MOD_NAME_CTRL, xkb::STATE_MODS_EFFECTIVE);
        let interpreted = if ctrl {
            match utf8.chars().next() {
                Some(ch) if ch.is_ascii_alphabetic() => Key::CtrlChar(ch.to_ascii_lowercase()),
                _ => Key::Other,
            }
        } else {
            use xkbcommon::xkb::keysyms;
            match symbol.raw() {
                keysyms::KEY_Escape => Key::Escape,
                keysyms::KEY_Return | keysyms::KEY_KP_Enter => Key::Enter,
                keysyms::KEY_Tab | keysyms::KEY_KP_Tab => Key::Tab,
                keysyms::KEY_BackSpace => Key::Backspace,
                keysyms::KEY_Up => Key::Up,
                keysyms::KEY_Down => Key::Down,
                keysyms::KEY_Page_Up => Key::PageUp,
                keysyms::KEY_Page_Down => Key::PageDown,
                keysyms::KEY_Home => Key::Home,
                keysyms::KEY_End => Key::End,
                _ => match utf8.chars().next() {
                    Some(ch) if !ch.is_control() => Key::Char(ch),
                    _ => Key::Other,
                },
            }
        };
        if let Some(action) = self.overlay.handle_key(interpreted) {
            self.exit = Some(action);
        }
        self.need_redraw = true;
    }

    fn handle_pointer_button(&mut self, button: u32, pressed: bool) {
        if button != 0x110 || !pressed {
            return;
        }
        let (x, y) = self.pointer_position;
        if let Some(action) = self.overlay.pointer_click(x, y) {
            self.exit = Some(action);
        }
        self.need_redraw = true;
    }

}

fn create_memfd(name: &str, len: usize) -> Result<OwnedFd, String> {
    let name = std::ffi::CString::new(name).map_err(|err| err.to_string())?;
    let fd = unsafe { libc::memfd_create(name.as_ptr(), libc::MFD_CLOEXEC) };
    if fd < 0 {
        return Err(format!(
            "memfd_create failed: {}",
            std::io::Error::last_os_error()
        ));
    }
    let fd = unsafe { OwnedFd::from_raw_fd(fd) };
    let result = unsafe { libc::ftruncate(fd.as_raw_fd(), len as libc::off_t) };
    if result < 0 {
        return Err(format!(
            "ftruncate failed: {}",
            std::io::Error::last_os_error()
        ));
    }
    Ok(fd)
}

// ---- Dispatch implementations -------------------------------------------------

impl Dispatch<wl_registry::WlRegistry, ()> for WaylandHost {
    fn event(
        state: &mut Self,
        registry: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _data: &(),
        _conn: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        match event {
            wl_registry::Event::Global {
                name,
                interface,
                version,
            } => match interface.as_str() {
                "wl_compositor" => {
                    state.globals.compositor =
                        Some(registry.bind(name, version.min(4), qh, ()));
                }
                "wl_shm" => {
                    state.globals.shm = Some(registry.bind(name, version.min(1), qh, ()));
                }
                "wl_seat" => {
                    state.globals.seat = Some(registry.bind(name, version.min(5), qh, ()));
                }
                "wl_output" => {
                    let output = registry.bind(name, version.min(2), qh, ());
                    if state.globals.output.is_none() {
                        state.globals.output = Some(output);
                    }
                }
                "zwlr_layer_shell_v1" => {
                    state.globals.layer_shell =
                        Some(registry.bind(name, version.min(4), qh, ()));
                }
                _ => {}
            },
            wl_registry::Event::GlobalRemove { .. } => {}
            _ => {}
        }
    }
}

impl Dispatch<wl_compositor::WlCompositor, ()> for WaylandHost {
    fn event(
        _state: &mut Self,
        _proxy: &wl_compositor::WlCompositor,
        _event: wl_compositor::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_surface::WlSurface, ()> for WaylandHost {
    fn event(
        _state: &mut Self,
        _proxy: &wl_surface::WlSurface,
        _event: wl_surface::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_region::WlRegion, ()> for WaylandHost {
    fn event(
        _state: &mut Self,
        _proxy: &wl_region::WlRegion,
        _event: wl_region::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_shm::WlShm, ()> for WaylandHost {
    fn event(
        _state: &mut Self,
        _proxy: &wl_shm::WlShm,
        _event: wl_shm::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_shm_pool::WlShmPool, ()> for WaylandHost {
    fn event(
        _state: &mut Self,
        _proxy: &wl_shm_pool::WlShmPool,
        _event: wl_shm_pool::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_buffer::WlBuffer, usize> for WaylandHost {
    fn event(
        state: &mut Self,
        _proxy: &wl_buffer::WlBuffer,
        event: wl_buffer::Event,
        data: &usize,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        if let wl_buffer::Event::Release = event {
            state.mark_buffer_released(*data);
        }
    }
}

impl Dispatch<wl_output::WlOutput, ()> for WaylandHost {
    fn event(
        state: &mut Self,
        _proxy: &wl_output::WlOutput,
        event: wl_output::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        if let wl_output::Event::Scale { factor } = event {
            state.globals.output_scale = state.globals.output_scale.max(factor);
        }
        if let wl_output::Event::Name { name } = event {
            state.globals.output_name = Some(name);
        }
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for WaylandHost {
    fn event(
        state: &mut Self,
        seat: &wl_seat::WlSeat,
        event: wl_seat::Event,
        _data: &(),
        _conn: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_seat::Event::Capabilities { capabilities } = event {
            let WEnum::Value(capabilities) = capabilities else {
                return;
            };
            if capabilities.contains(wl_seat::Capability::Keyboard) && state.keyboard.is_none() {
                state.keyboard = Some(KeyboardState {
                    keyboard: seat.get_keyboard(qh, ()),
                    context: xkb::Context::new(xkb::CONTEXT_NO_FLAGS),
                    keymap: None,
                    state: None,
                });
            } else if !capabilities.contains(wl_seat::Capability::Keyboard) {
                if let Some(keyboard) = state.keyboard.take() {
                    keyboard.keyboard.release();
                }
            }
            let has_pointer = capabilities.contains(wl_seat::Capability::Pointer);
            if has_pointer && state.pointer.is_none() {
                state.pointer = Some(seat.get_pointer(qh, ()));
            } else if !has_pointer {
                if let Some(pointer) = state.pointer.take() {
                    pointer.release();
                }
            }
        }
    }
}

impl Dispatch<wl_keyboard::WlKeyboard, ()> for WaylandHost {
    fn event(
        state: &mut Self,
        _proxy: &wl_keyboard::WlKeyboard,
        event: wl_keyboard::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        match event {
            wl_keyboard::Event::Keymap { format, fd, size } => {
                if !matches!(format, WEnum::Value(wl_keyboard::KeymapFormat::XkbV1)) {
                    return;
                }
                let Some(keyboard) = &mut state.keyboard else {
                    return;
                };
                let mut bytes = Vec::with_capacity(size as usize);
                let file = std::fs::File::from(fd);
                if file.take(size as u64).read_to_end(&mut bytes).is_err() {
                    return;
                }
                let text = String::from_utf8_lossy(&bytes).to_string();
                keyboard.context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
                let Some(keymap) = xkb::Keymap::new_from_string(
                    &keyboard.context,
                    text,
                    xkb::KEYMAP_FORMAT_TEXT_V1,
                    xkb::KEYMAP_COMPILE_NO_FLAGS,
                ) else {
                    return;
                };
                keyboard.state = Some(xkb::State::new(&keymap));
                keyboard.keymap = Some(keymap);
            }
            wl_keyboard::Event::Key {
                key,
                state: key_state,
                ..
            } => {
                let pressed = matches!(key_state, WEnum::Value(wl_keyboard::KeyState::Pressed));
                state.handle_key(key, pressed);
            }
            wl_keyboard::Event::Modifiers {
                mods_depressed,
                mods_latched,
                mods_locked,
                group,
                ..
            } => {
                if let Some(keyboard) = &mut state.keyboard {
                    if let Some(xkb_state) = &mut keyboard.state {
                        xkb_state.update_mask(
                            mods_depressed,
                            mods_latched,
                            mods_locked,
                            0,
                            0,
                            group,
                        );
                    }
                }
            }
            _ => {}
        }
    }
}

impl Dispatch<wl_pointer::WlPointer, ()> for WaylandHost {
    fn event(
        state: &mut Self,
        pointer: &wl_pointer::WlPointer,
        event: wl_pointer::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        match event {
            wl_pointer::Event::Enter {
                serial,
                surface_x,
                surface_y,
                ..
            } => {
                state.pointer_position = (surface_x as f32, surface_y as f32);
                pointer.set_cursor(serial, None, 0, 0);
            }
            wl_pointer::Event::Motion {
                surface_x,
                surface_y,
                ..
            } => {
                state.pointer_position = (surface_x as f32, surface_y as f32);
            }
            wl_pointer::Event::Button {
                button,
                state: button_state,
                ..
            } => {
                let pressed = matches!(
                    button_state,
                    WEnum::Value(wl_pointer::ButtonState::Pressed)
                );
                state.handle_pointer_button(button, pressed);
            }
            wl_pointer::Event::Axis { axis, .. } => {
                if matches!(axis, WEnum::Value(wl_pointer::Axis::VerticalScroll)) {
                    // The value arrives in the following axis_value events; a
                    // simple one-step scroll per event is enough for this UI.
                }
            }
            _ => {}
        }
    }
}

impl Dispatch<zwlr_layer_shell_v1::ZwlrLayerShellV1, ()> for WaylandHost {
    fn event(
        _state: &mut Self,
        _proxy: &zwlr_layer_shell_v1::ZwlrLayerShellV1,
        _event: zwlr_layer_shell_v1::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<zwlr_layer_surface_v1::ZwlrLayerSurfaceV1, ()> for WaylandHost {
    fn event(
        state: &mut Self,
        _proxy: &zwlr_layer_surface_v1::ZwlrLayerSurfaceV1,
        event: zwlr_layer_surface_v1::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        match event {
            zwlr_layer_surface_v1::Event::Configure {
                serial,
                width,
                height,
            } => {
                if let Some(layer) = &state.layer {
                    layer.layer_surface.ack_configure(serial);
                }
                let width = if width == 0 {
                    DEFAULT_WIDTH
                } else {
                    width as u32
                };
                let height = if height == 0 {
                    DEFAULT_HEIGHT
                } else {
                    height as u32
                };
                state.configured = true;
                state.scale = state.globals.output_scale.max(1) as f32;
                state.width_px = width.saturating_mul(state.scale as u32).max(1);
                state.height_px = height.saturating_mul(state.scale as u32).max(1);
                if let Some(layer) = &state.layer {
                    layer
                        .surface
                        .set_buffer_scale(state.scale.max(1.0) as i32);
                }
                state.need_redraw = true;
            }
            zwlr_layer_surface_v1::Event::Closed => {
                state.exit = Some(state.overlay.close("compositor-closed"));
            }
            _ => {}
        }
    }
}

