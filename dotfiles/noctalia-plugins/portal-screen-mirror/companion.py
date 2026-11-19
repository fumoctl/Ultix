#!/usr/bin/env python3
"""Noctalia Portal Screen Mirror companion: XDG ScreenCast / wlr-screencopy -> PixelStream."""

from __future__ import annotations

import argparse
import array
import ctypes
import ctypes.util
import fcntl
import json
import math
import mmap
import os
import signal
import socket
import struct
import subprocess
import sys
import threading
import time

import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gio, GLib, Gst

HELLO_MSG = 1
REQUEST_MSG = 2
BUFFER_MSG = 1
FRAME_MSG = 2
PROTO_VERSION = 1
MAX_DIM = 4096
MAX_PIXELS = 4096 * 1024

WL_MARSHAL_FLAG_DESTROY = 1 << 0
SHM_FORMAT_MAP = {
    0: "BGRA",        # WL_SHM_FORMAT_ARGB8888
    1: "BGRx",        # WL_SHM_FORMAT_XRGB8888
    0x34325241: "BGRA",  # DRM_FORMAT_ARGB8888
    0x34325258: "BGRx",  # DRM_FORMAT_XRGB8888
    0x34324241: "RGBA",  # DRM_FORMAT_ABGR8888
    0x34324258: "RGBx",  # DRM_FORMAT_XBGR8888
    0x30335241: "BGR10A2_LE",  # DRM_FORMAT_ARGB2101010
    0x30335258: "BGR10A2_LE",  # DRM_FORMAT_XRGB2101010
    0x30334241: "RGB10A2_LE",  # DRM_FORMAT_ABGR2101010
    0x30334258: "RGB10A2_LE",  # DRM_FORMAT_XBGR2101010
}


def emit(line: str) -> None:
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def clamp_max_dims(width: int, height: int) -> tuple[int, int]:
    w = min(max(width, 64), MAX_DIM)
    h = min(max(height, 64), MAX_DIM)
    if w * h > MAX_PIXELS:
        scale = math.sqrt(MAX_PIXELS / float(w * h))
        w = max(64, int(w * scale) & ~1)
        h = max(64, int(h * scale) & ~1)
    return w, h


def load_tokens(path: str) -> dict[str, str]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, dict):
                return {str(k): str(v) for k, v in data.items() if isinstance(v, str)}
    except (OSError, ValueError):
        pass
    return {}


def save_tokens(path: str, tokens: dict[str, str]) -> None:
    tmp = path + ".tmp"
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(tokens, f)
        os.replace(tmp, path)
    except OSError:
        pass


def pick_region(outputs: list[dict]) -> tuple[dict | None, tuple[int, int, int, int] | None, bool, str | None]:
    try:
        proc = subprocess.run(["slurp", "-f", "%x %y %w %h"], capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return None, None, False, "slurp is not installed"
    if proc.returncode != 0:
        return None, None, True, None
    parts = proc.stdout.strip().split()
    if len(parts) != 4:
        return None, None, True, None
    try:
        rx, ry, rw, rh = (int(p) for p in parts)
    except ValueError:
        return None, None, True, None
    if rw < 2 or rh < 2:
        return None, None, True, None

    best_out = None
    best_area = -1
    for out in outputs:
        ox = int(out.get("x") or 0)
        oy = int(out.get("y") or 0)
        ow = int(out.get("width") or 0)
        oh = int(out.get("height") or 0)
        if ow <= 0 or oh <= 0:
            continue
        ix0 = max(rx, ox)
        iy0 = max(ry, oy)
        ix1 = min(rx + rw, ox + ow)
        iy1 = min(ry + rh, oy + oh)
        area = max(0, ix1 - ix0) * max(0, iy1 - iy0)
        if area > best_area:
            best_area = area
            best_out = out

    return best_out, (rx, ry, rw, rh), False, None


class PixelStreamServer:
    """Double-buffered sealed memfd SOCK_SEQPACKET server for Noctalia's ui.pixelStream."""

    def __init__(self, socket_path: str) -> None:
        self.socket_path = socket_path
        self.srv_sock: socket.socket | None = None
        self.client_sock: socket.socket | None = None
        self.srv_watch = 0
        self.client_watch = 0
        self.slots: list[dict | None] = [None, None]
        self.next_slot = 0
        self.slot_gen = 0
        self.frame_lock = threading.Lock()
        self.latest = {"seq": 0, "w": 0, "h": 0, "data": None, "idle_scheduled": False}
        self.conn_state = {"hello": False, "requested": False, "attached_gen": [-1, -1], "last_seq": 0}
        self.ready_emitted = False

    def start(self) -> None:
        try:
            os.unlink(self.socket_path)
        except OSError:
            pass
        self.srv_sock = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        self.srv_sock.setblocking(False)
        self.srv_sock.bind(self.socket_path)
        os.chmod(self.socket_path, 0o600)
        self.srv_sock.listen(2)
        self.srv_watch = GLib.io_add_watch(
            self.srv_sock.fileno(),
            GLib.PRIORITY_DEFAULT,
            GLib.IOCondition.IN,
            self._on_accept,
        )

    def submit_rgba(self, w: int, h: int, raw: bytes) -> None:
        with self.frame_lock:
            self.latest["seq"] += 1
            self.latest["w"] = w
            self.latest["h"] = h
            self.latest["data"] = raw
            need_sched = not self.latest["idle_scheduled"]
            if need_sched:
                self.latest["idle_scheduled"] = True
        if need_sched:
            GLib.idle_add(self._deliver_if_ready)

    def attach_appsink(self, sink_elem: Gst.Element) -> None:
        def on_new_sample(sink: Gst.Element) -> Gst.FlowReturn:
            sample = sink.emit("pull-sample")
            if sample is None:
                return Gst.FlowReturn.OK
            caps = sample.get_caps()
            buf = sample.get_buffer()
            if caps is None or buf is None:
                return Gst.FlowReturn.OK
            s = caps.get_structure(0)
            ok_w, w = s.get_int("width")
            ok_h, h = s.get_int("height")
            if not (ok_w and ok_h) or w <= 0 or h <= 0 or w * h > MAX_PIXELS:
                return Gst.FlowReturn.OK
            expected = w * h * 4
            ok_map, mapinfo = buf.map(Gst.MapFlags.READ)
            if not ok_map:
                return Gst.FlowReturn.OK
            try:
                if mapinfo.size < expected:
                    return Gst.FlowReturn.OK
                raw = bytes(memoryview(mapinfo.data)[:expected])
            finally:
                buf.unmap(mapinfo)
            self.submit_rgba(w, h, raw)
            return Gst.FlowReturn.OK

        sink_elem.connect("new-sample", on_new_sample)

    def _ensure_slot(self, idx: int, w: int, h: int) -> dict:
        cur = self.slots[idx]
        if cur is not None and cur["dims"] == (w, h):
            return cur
        self._free_slot(idx)
        byte_len = w * h * 4
        fd = os.memfd_create(f"noctalia-mirror-{idx}", os.MFD_CLOEXEC | os.MFD_ALLOW_SEALING)
        os.ftruncate(fd, byte_len)
        fcntl.fcntl(fd, fcntl.F_ADD_SEALS, fcntl.F_SEAL_SHRINK)
        mm = mmap.mmap(fd, byte_len, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
        self.slot_gen += 1
        entry = {"fd": fd, "mm": mm, "dims": (w, h), "gen": self.slot_gen}
        self.slots[idx] = entry
        return entry

    def _free_slot(self, idx: int) -> None:
        slot = self.slots[idx]
        self.slots[idx] = None
        if slot is not None:
            try:
                slot["mm"].close()
            except Exception:
                pass
            try:
                os.close(slot["fd"])
            except OSError:
                pass

    def _deliver_if_ready(self) -> bool:
        with self.frame_lock:
            self.latest["idle_scheduled"] = False
            seq_val = self.latest["seq"]
            w = self.latest["w"]
            h = self.latest["h"]
            data = self.latest["data"]

        if data is not None and not self.ready_emitted:
            self.ready_emitted = True
            emit("ready")

        if self.client_sock is None or not self.conn_state["requested"] or data is None or seq_val <= self.conn_state["last_seq"]:
            return GLib.SOURCE_REMOVE

        slot_idx = self.next_slot
        self.next_slot = 1 - self.next_slot
        try:
            slot = self._ensure_slot(slot_idx, w, h)
            slot["mm"].seek(0)
            slot["mm"].write(data)
            if self.conn_state["attached_gen"][slot_idx] != slot["gen"]:
                self.client_sock.sendmsg(
                    [struct.pack("<IIII", BUFFER_MSG, slot_idx, w, h)],
                    [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", [slot["fd"]]))],
                )
                self.conn_state["attached_gen"][slot_idx] = slot["gen"]
            self.client_sock.send(struct.pack("<II", FRAME_MSG, slot_idx))
            self.conn_state["requested"] = False
            self.conn_state["last_seq"] = seq_val
        except OSError:
            self.close_client()
        return GLib.SOURCE_REMOVE

    def _on_client_io(self, _fd: int, cond: GLib.IOCondition) -> bool:
        if self.client_sock is None:
            return GLib.SOURCE_REMOVE
        if cond & (GLib.IOCondition.ERR | GLib.IOCondition.NVAL):
            self.close_client()
            return GLib.SOURCE_REMOVE
        while self.client_sock is not None:
            try:
                pkt = self.client_sock.recv(64)
            except BlockingIOError:
                break
            except OSError:
                self.close_client()
                return GLib.SOURCE_REMOVE
            if not pkt or len(pkt) != 8:
                self.close_client()
                return GLib.SOURCE_REMOVE
            msg_type, arg = struct.unpack("<II", pkt)
            if msg_type == HELLO_MSG:
                if arg != PROTO_VERSION:
                    self.close_client()
                    return GLib.SOURCE_REMOVE
                self.conn_state["hello"] = True
            elif msg_type == REQUEST_MSG and self.conn_state["hello"]:
                self.conn_state["requested"] = True
                self._deliver_if_ready()
            else:
                self.close_client()
                return GLib.SOURCE_REMOVE
        return GLib.SOURCE_CONTINUE

    def _on_accept(self, _fd: int, _cond: GLib.IOCondition) -> bool:
        if self.srv_sock is None:
            return GLib.SOURCE_REMOVE
        try:
            conn, _ = self.srv_sock.accept()
        except OSError:
            return GLib.SOURCE_CONTINUE
        self.close_client()
        conn.setblocking(False)
        self.client_sock = conn
        self.conn_state = {"hello": False, "requested": False, "attached_gen": [-1, -1], "last_seq": 0}
        self.client_watch = GLib.io_add_watch(
            conn.fileno(),
            GLib.PRIORITY_DEFAULT,
            GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
            self._on_client_io,
        )
        return GLib.SOURCE_CONTINUE

    def close_client(self) -> None:
        if self.client_watch:
            GLib.source_remove(self.client_watch)
            self.client_watch = 0
        if self.client_sock is not None:
            try:
                self.client_sock.close()
            except OSError:
                pass
            self.client_sock = None

    def close(self) -> None:
        self.close_client()
        if self.srv_watch:
            GLib.source_remove(self.srv_watch)
            self.srv_watch = 0
        if self.srv_sock is not None:
            try:
                self.srv_sock.close()
            except OSError:
                pass
            self.srv_sock = None
        try:
            os.unlink(self.socket_path)
        except OSError:
            pass
        self._free_slot(0)
        self._free_slot(1)


class _WlMessage(ctypes.Structure):
    pass


class _WlInterface(ctypes.Structure):
    pass


_WlMessage._fields_ = [
    ("name", ctypes.c_char_p),
    ("signature", ctypes.c_char_p),
    ("types", ctypes.POINTER(ctypes.POINTER(_WlInterface))),
]
_WlInterface._fields_ = [
    ("name", ctypes.c_char_p),
    ("version", ctypes.c_int),
    ("method_count", ctypes.c_int),
    ("methods", ctypes.POINTER(_WlMessage)),
    ("event_count", ctypes.c_int),
    ("events", ctypes.POINTER(_WlMessage)),
]


def try_run_wlr_screencopy_region(
    stream_srv: PixelStreamServer,
    output_info: dict,
    region_box: tuple[int, int, int, int],
    cursor_mode: int,
    max_w: int,
    max_h: int,
    should_continue,
) -> tuple[bool, int]:
    """Capture an output sub-rectangle directly via zwlr_screencopy_manager_v1 (no portal picker).

    Returns `(supported, exit_code)`. When `supported` is False, the caller can fall back to XDG ScreenCast.
    """
    out_name = str(output_info.get("name") or "")
    ox = int(output_info.get("x") or 0)
    oy = int(output_info.get("y") or 0)
    ow = int(output_info.get("width") or 0)
    oh = int(output_info.get("height") or 0)
    if not out_name or ow < 2 or oh < 2:
        return False, 0

    rx, ry, rw, rh = region_box
    lx = max(0, min(ow - 2, rx - ox))
    ly = max(0, min(oh - 2, ry - oy))
    lw = max(2, min(ow - lx, rx + rw - (ox + lx)))
    lh = max(2, min(oh - ly, ry + rh - (oy + ly)))

    try:
        libwl = ctypes.CDLL("libwayland-client.so.0")
    except OSError:
        libwl_name = ctypes.util.find_library("wayland-client")
        if not libwl_name:
            return False, 0
        try:
            libwl = ctypes.CDLL(libwl_name)
        except OSError:
            return False, 0

    wl_registry_iface = _WlInterface.in_dll(libwl, "wl_registry_interface")
    wl_shm_iface = _WlInterface.in_dll(libwl, "wl_shm_interface")
    wl_shm_pool_iface = _WlInterface.in_dll(libwl, "wl_shm_pool_interface")
    wl_buffer_iface = _WlInterface.in_dll(libwl, "wl_buffer_interface")
    wl_output_iface = _WlInterface.in_dll(libwl, "wl_output_interface")

    null_iface = ctypes.POINTER(_WlInterface)()
    frame_iface = _WlInterface()
    mgr_iface = _WlInterface()

    t_buf = (ctypes.POINTER(_WlInterface) * 1)(ctypes.pointer(wl_buffer_iface))
    t_null4 = (ctypes.POINTER(_WlInterface) * 4)(null_iface, null_iface, null_iface, null_iface)
    t_null3 = (ctypes.POINTER(_WlInterface) * 3)(null_iface, null_iface, null_iface)
    t_null1 = (ctypes.POINTER(_WlInterface) * 1)(null_iface)

    frame_methods = (_WlMessage * 3)(
        _WlMessage(b"copy", b"o", t_buf),
        _WlMessage(b"destroy", b"", None),
        _WlMessage(b"copy_with_damage", b"2o", t_buf),
    )
    frame_events = (_WlMessage * 5)(
        _WlMessage(b"buffer", b"uuuu", t_null4),
        _WlMessage(b"flags", b"u", t_null1),
        _WlMessage(b"ready", b"uuu", t_null3),
        _WlMessage(b"failed", b"", None),
        _WlMessage(b"damage", b"2uuuu", t_null4),
    )
    frame_iface.name = b"zwlr_screencopy_frame_v1"
    frame_iface.version = 2
    frame_iface.method_count = 3
    frame_iface.methods = frame_methods
    frame_iface.event_count = 5
    frame_iface.events = frame_events

    t_cap_out = (ctypes.POINTER(_WlInterface) * 3)(
        ctypes.pointer(frame_iface), null_iface, ctypes.pointer(wl_output_iface)
    )
    t_cap_reg = (ctypes.POINTER(_WlInterface) * 7)(
        ctypes.pointer(frame_iface),
        null_iface,
        ctypes.pointer(wl_output_iface),
        null_iface,
        null_iface,
        null_iface,
        null_iface,
    )
    mgr_methods = (_WlMessage * 3)(
        _WlMessage(b"capture_output", b"nio", t_cap_out),
        _WlMessage(b"capture_output_region", b"nioiiii", t_cap_reg),
        _WlMessage(b"destroy", b"", None),
    )
    mgr_iface.name = b"zwlr_screencopy_manager_v1"
    mgr_iface.version = 2
    mgr_iface.method_count = 3
    mgr_iface.methods = mgr_methods
    mgr_iface.event_count = 0
    mgr_iface.events = None

    libwl.wl_display_connect.argtypes = [ctypes.c_char_p]
    libwl.wl_display_connect.restype = ctypes.c_void_p
    libwl.wl_display_disconnect.argtypes = [ctypes.c_void_p]
    libwl.wl_display_get_fd.argtypes = [ctypes.c_void_p]
    libwl.wl_display_get_fd.restype = ctypes.c_int
    libwl.wl_display_roundtrip.argtypes = [ctypes.c_void_p]
    libwl.wl_display_roundtrip.restype = ctypes.c_int
    libwl.wl_display_flush.argtypes = [ctypes.c_void_p]
    libwl.wl_display_flush.restype = ctypes.c_int
    libwl.wl_display_dispatch_pending.argtypes = [ctypes.c_void_p]
    libwl.wl_display_dispatch_pending.restype = ctypes.c_int
    libwl.wl_display_prepare_read.argtypes = [ctypes.c_void_p]
    libwl.wl_display_prepare_read.restype = ctypes.c_int
    libwl.wl_display_read_events.argtypes = [ctypes.c_void_p]
    libwl.wl_display_read_events.restype = ctypes.c_int
    libwl.wl_display_cancel_read.argtypes = [ctypes.c_void_p]
    libwl.wl_proxy_marshal_flags.restype = ctypes.c_void_p
    libwl.wl_proxy_add_listener.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    libwl.wl_proxy_add_listener.restype = ctypes.c_int
    libwl.wl_proxy_destroy.argtypes = [ctypes.c_void_p]

    dpy = libwl.wl_display_connect(None)
    if not dpy:
        return False, 0

    refs: list = [frame_methods, frame_events, mgr_methods, t_buf, t_null4, t_null3, t_null1, t_cap_out, t_cap_reg]
    wl_state: dict = {
        "shm": None,
        "mgr": None,
        "mgr_ver": 0,
        "outputs": [],
        "shm_slot": None,
        "active_frame": None,
    }
    pipeline: Gst.Pipeline | None = None
    wl_watch = 0
    pace_timer = 0
    run_timer = 0
    sig_ids: list[int] = []

    def free_shm_slot() -> None:
        slot = wl_state["shm_slot"]
        wl_state["shm_slot"] = None
        if slot is not None:
            if slot.get("buf"):
                libwl.wl_proxy_marshal_flags(
                    ctypes.c_void_p(slot["buf"]),
                    ctypes.c_uint32(0),
                    None,
                    ctypes.c_uint32(1),
                    ctypes.c_uint32(WL_MARSHAL_FLAG_DESTROY),
                )
            if slot.get("pool"):
                libwl.wl_proxy_marshal_flags(
                    ctypes.c_void_p(slot["pool"]),
                    ctypes.c_uint32(1),
                    None,
                    ctypes.c_uint32(1),
                    ctypes.c_uint32(WL_MARSHAL_FLAG_DESTROY),
                )
            try:
                slot["mm"].close()
            except Exception:
                pass
            try:
                os.close(slot["fd"])
            except OSError:
                pass

    def destroy_active_frame() -> None:
        fr = wl_state["active_frame"]
        wl_state["active_frame"] = None
        if fr:
            libwl.wl_proxy_marshal_flags(
                ctypes.c_void_p(fr),
                ctypes.c_uint32(1),
                None,
                ctypes.c_uint32(wl_state["mgr_ver"]),
                ctypes.c_uint32(WL_MARSHAL_FLAG_DESTROY),
            )

    try:
        reg = libwl.wl_proxy_marshal_flags(
            ctypes.c_void_p(dpy),
            ctypes.c_uint32(1),
            ctypes.byref(wl_registry_iface),
            ctypes.c_uint32(1),
            ctypes.c_uint32(0),
            ctypes.c_void_p(None),
        )

        GLOBAL_CB = ctypes.CFUNCTYPE(
            None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_uint32
        )
        GLOBAL_RM_CB = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32)

        def on_global(_data, registry, name, iface_bytes, version):
            iface = iface_bytes.decode("utf-8", "replace") if iface_bytes else ""
            if iface == "wl_shm" and wl_state["shm"] is None:
                wl_state["shm"] = libwl.wl_proxy_marshal_flags(
                    ctypes.c_void_p(registry),
                    ctypes.c_uint32(0),
                    ctypes.byref(wl_shm_iface),
                    ctypes.c_uint32(1),
                    ctypes.c_uint32(0),
                    ctypes.c_uint32(name),
                    wl_shm_iface.name,
                    ctypes.c_uint32(1),
                    ctypes.c_void_p(None),
                )
            elif iface == "zwlr_screencopy_manager_v1" and wl_state["mgr"] is None:
                v = min(int(version), 2)
                wl_state["mgr_ver"] = v
                wl_state["mgr"] = libwl.wl_proxy_marshal_flags(
                    ctypes.c_void_p(registry),
                    ctypes.c_uint32(0),
                    ctypes.byref(mgr_iface),
                    ctypes.c_uint32(v),
                    ctypes.c_uint32(0),
                    ctypes.c_uint32(name),
                    mgr_iface.name,
                    ctypes.c_uint32(v),
                    ctypes.c_void_p(None),
                )
            elif iface == "wl_output" and version >= 4:
                out_ver = min(int(version), 4)
                out_proxy = libwl.wl_proxy_marshal_flags(
                    ctypes.c_void_p(registry),
                    ctypes.c_uint32(0),
                    ctypes.byref(wl_output_iface),
                    ctypes.c_uint32(out_ver),
                    ctypes.c_uint32(0),
                    ctypes.c_uint32(name),
                    wl_output_iface.name,
                    ctypes.c_uint32(out_ver),
                    ctypes.c_void_p(None),
                )
                wl_state["outputs"].append({"proxy": out_proxy, "ver": out_ver, "name": "", "global_name": int(name)})

        def on_global_rm(_data, _registry, removed_name):
            for entry in wl_state["outputs"]:
                if entry["global_name"] == int(removed_name) and entry["name"] == out_name:
                    main_loop.quit()

        cb_global = GLOBAL_CB(on_global)
        cb_global_rm = GLOBAL_RM_CB(on_global_rm)
        reg_listener = (ctypes.c_void_p * 2)(
            ctypes.cast(cb_global, ctypes.c_void_p),
            ctypes.cast(cb_global_rm, ctypes.c_void_p),
        )
        refs.extend([cb_global, cb_global_rm, reg_listener])
        libwl.wl_proxy_add_listener(reg, ctypes.byref(reg_listener), None)
        libwl.wl_display_roundtrip(dpy)

        if not wl_state["mgr"] or not wl_state["shm"] or not wl_state["outputs"]:
            return False, 0

        OUT_GEOM = ctypes.CFUNCTYPE(
            None,
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_int32,
            ctypes.c_int32,
            ctypes.c_int32,
            ctypes.c_int32,
            ctypes.c_int32,
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_int32,
        )
        OUT_MODE = ctypes.CFUNCTYPE(
            None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int32, ctypes.c_int32, ctypes.c_int32
        )
        OUT_DONE = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p)
        OUT_SCALE = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int32)
        OUT_NAME = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p)
        OUT_DESC = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p)

        c_noop_geom = OUT_GEOM(lambda *_a: None)
        c_noop_mode = OUT_MODE(lambda *_a: None)
        c_noop_done = OUT_DONE(lambda *_a: None)
        c_noop_scale = OUT_SCALE(lambda *_a: None)
        c_noop_desc = OUT_DESC(lambda *_a: None)
        refs.extend([c_noop_geom, c_noop_mode, c_noop_done, c_noop_scale, c_noop_desc])

        for entry in wl_state["outputs"]:
            def make_name_cb(target_entry):
                def _cb(_d, _o, nm):
                    target_entry["name"] = nm.decode("utf-8", "replace") if nm else ""
                return OUT_NAME(_cb)

            c_name = make_name_cb(entry)
            lst = (ctypes.c_void_p * 6)(
                ctypes.cast(c_noop_geom, ctypes.c_void_p),
                ctypes.cast(c_noop_mode, ctypes.c_void_p),
                ctypes.cast(c_noop_done, ctypes.c_void_p),
                ctypes.cast(c_noop_scale, ctypes.c_void_p),
                ctypes.cast(c_name, ctypes.c_void_p),
                ctypes.cast(c_noop_desc, ctypes.c_void_p),
            )
            refs.extend([c_name, lst])
            libwl.wl_proxy_add_listener(entry["proxy"], ctypes.byref(lst), None)

        libwl.wl_display_roundtrip(dpy)

        target_out = next((o["proxy"] for o in wl_state["outputs"] if o["name"] == out_name), None)
        if not target_out:
            return False, 0

        main_loop = GLib.MainLoop()
        stream_srv.start()

        pipeline = Gst.parse_launch(
            "appsrc name=src is-live=true do-timestamp=true format=time max-buffers=1 leaky-type=downstream "
            "! videoflip name=flip "
            "! videoconvert ! video/x-raw,format=RGBx,pixel-aspect-ratio=1/1 "
            "! videoscale ! videoconvert "
            f"! video/x-raw,format=RGBA,width=[1,{max_w}],height=[1,{max_h}],pixel-aspect-ratio=1/1 "
            "! appsink name=sink max-buffers=1 drop=true emit-signals=true sync=false"
        )
        appsrc = pipeline.get_by_name("src")
        flip_elem = pipeline.get_by_name("flip")
        stream_srv.attach_appsink(pipeline.get_by_name("sink"))

        err_box: dict[str, str] = {}
        gst_bus = pipeline.get_bus()
        gst_bus.add_signal_watch()

        def on_gst_msg(_b, msg):
            if msg.type == Gst.MessageType.EOS:
                main_loop.quit()
            elif msg.type == Gst.MessageType.ERROR:
                err, _dbg = msg.parse_error()
                err_box["msg"] = err.message
                main_loop.quit()

        gst_bus.connect("message", on_gst_msg)

        if pipeline.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
            emit("error:Failed to start region scaler pipeline")
            return True, 1

        cap_ctx = {
            "first": True,
            "flags": 0,
            "last_caps_key": None,
            "flipped": False,
            "failed_streak": 0,
        }

        F_BUF = ctypes.CFUNCTYPE(
            None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32
        )
        F_FLAGS = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32)
        F_READY = ctypes.CFUNCTYPE(
            None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32
        )
        F_FAIL = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p)
        F_DMG = ctypes.CFUNCTYPE(
            None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32
        )

        def ensure_shm_slot(fmt: int, w: int, h: int, stride: int) -> dict | None:
            cur = wl_state["shm_slot"]
            if cur is not None and (cur["fmt"], cur["w"], cur["h"], cur["stride"]) == (fmt, w, h, stride):
                return cur
            free_shm_slot()
            size = stride * h
            if size <= 0:
                return None
            fd = os.memfd_create("noctalia-screencopy", os.MFD_CLOEXEC)
            os.ftruncate(fd, size)
            mm = mmap.mmap(fd, size, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
            pool = libwl.wl_proxy_marshal_flags(
                ctypes.c_void_p(wl_state["shm"]),
                ctypes.c_uint32(0),
                ctypes.byref(wl_shm_pool_iface),
                ctypes.c_uint32(1),
                ctypes.c_uint32(0),
                ctypes.c_void_p(None),
                ctypes.c_int32(fd),
                ctypes.c_int32(size),
            )
            buf = libwl.wl_proxy_marshal_flags(
                ctypes.c_void_p(pool),
                ctypes.c_uint32(0),
                ctypes.byref(wl_buffer_iface),
                ctypes.c_uint32(1),
                ctypes.c_uint32(0),
                ctypes.c_void_p(None),
                ctypes.c_int32(0),
                ctypes.c_int32(w),
                ctypes.c_int32(h),
                ctypes.c_int32(stride),
                ctypes.c_uint32(fmt),
            )
            slot = {"fmt": fmt, "w": w, "h": h, "stride": stride, "size": size, "fd": fd, "mm": mm, "pool": pool, "buf": buf}
            wl_state["shm_slot"] = slot
            return slot

        def schedule_next_frame(delay_ms: int) -> None:
            nonlocal pace_timer
            if pace_timer:
                return

            def _fire() -> bool:
                nonlocal pace_timer
                pace_timer = 0
                request_capture_frame()
                return GLib.SOURCE_REMOVE

            pace_timer = GLib.timeout_add(delay_ms, _fire)

        def on_f_buf(_d, fr, fmt, w, h, stride):
            if int(fmt) not in SHM_FORMAT_MAP or w == 0 or h == 0 or stride < w * 4:
                err_box["msg"] = f"Unsupported screencopy buffer format (0x{int(fmt):x})"
                destroy_active_frame()
                main_loop.quit()
                return
            slot = ensure_shm_slot(int(fmt), int(w), int(h), int(stride))
            if slot is None:
                err_box["msg"] = "Failed to allocate screencopy SHM buffer"
                destroy_active_frame()
                main_loop.quit()
                return
            use_damage = (not cap_ctx["first"]) and wl_state["mgr_ver"] >= 2
            opcode = 2 if use_damage else 0
            libwl.wl_proxy_marshal_flags(
                ctypes.c_void_p(fr),
                ctypes.c_uint32(opcode),
                None,
                ctypes.c_uint32(wl_state["mgr_ver"]),
                ctypes.c_uint32(0),
                ctypes.c_void_p(slot["buf"]),
            )
            libwl.wl_display_flush(dpy)

        def on_f_flags(_d, _fr, fl):
            cap_ctx["flags"] = int(fl)

        def on_f_ready(_d, _fr, _hi, _lo, _ns):
            destroy_active_frame()
            cap_ctx["first"] = False
            cap_ctx["failed_streak"] = 0
            slot = wl_state["shm_slot"]
            if slot is None:
                return
            w = slot["w"]
            h = slot["h"]
            stride = slot["stride"]
            gst_fmt = SHM_FORMAT_MAP[slot["fmt"]]

            want_flip = bool(cap_ctx["flags"] & 1)
            if want_flip != cap_ctx["flipped"]:
                Gst.util_set_object_arg(flip_elem, "method", "vertical-flip" if want_flip else "none")
                cap_ctx["flipped"] = want_flip

            caps_key = (gst_fmt, w, h)
            if caps_key != cap_ctx["last_caps_key"]:
                caps = Gst.Caps.from_string(
                    f"video/x-raw,format={gst_fmt},width={w},height={h},framerate=0/1,pixel-aspect-ratio=1/1"
                )
                appsrc.set_property("caps", caps)
                cap_ctx["last_caps_key"] = caps_key

            row_bytes = w * 4
            mm = slot["mm"]
            if stride == row_bytes:
                payload = bytes(memoryview(mm)[: row_bytes * h])
            else:
                mv = memoryview(mm)
                payload = b"".join(bytes(mv[y * stride : y * stride + row_bytes]) for y in range(h))

            appsrc.emit("push-buffer", Gst.Buffer.new_wrapped(payload))
            schedule_next_frame(16)

        def on_f_fail(_d, _fr):
            destroy_active_frame()
            cap_ctx["failed_streak"] += 1
            if cap_ctx["failed_streak"] >= 5:
                err_box["msg"] = "Compositor rejected region capture"
                main_loop.quit()
                return
            schedule_next_frame(50)

        cb_b = F_BUF(on_f_buf)
        cb_fl = F_FLAGS(on_f_flags)
        cb_r = F_READY(on_f_ready)
        cb_fa = F_FAIL(on_f_fail)
        cb_dm = F_DMG(lambda *_a: None)
        frame_listener = (ctypes.c_void_p * 5)(
            ctypes.cast(cb_b, ctypes.c_void_p),
            ctypes.cast(cb_fl, ctypes.c_void_p),
            ctypes.cast(cb_r, ctypes.c_void_p),
            ctypes.cast(cb_fa, ctypes.c_void_p),
            ctypes.cast(cb_dm, ctypes.c_void_p),
        )
        refs.extend([cb_b, cb_fl, cb_r, cb_fa, cb_dm, frame_listener])

        overlay_cursor = 1 if cursor_mode == 2 else 0

        def request_capture_frame() -> None:
            if wl_state["active_frame"] is not None or not should_continue():
                return
            cap_ctx["flags"] = 0
            fr = libwl.wl_proxy_marshal_flags(
                ctypes.c_void_p(wl_state["mgr"]),
                ctypes.c_uint32(1),
                ctypes.byref(frame_iface),
                ctypes.c_uint32(wl_state["mgr_ver"]),
                ctypes.c_uint32(0),
                ctypes.c_void_p(None),
                ctypes.c_int32(overlay_cursor),
                ctypes.c_void_p(target_out),
                ctypes.c_int32(lx),
                ctypes.c_int32(ly),
                ctypes.c_int32(lw),
                ctypes.c_int32(lh),
            )
            if not fr:
                err_box["msg"] = "Failed to create screencopy frame"
                main_loop.quit()
                return
            wl_state["active_frame"] = fr
            libwl.wl_proxy_add_listener(fr, ctypes.byref(frame_listener), None)
            libwl.wl_display_flush(dpy)

        def on_wl_io(_fd: int, cond: GLib.IOCondition) -> bool:
            if cond & (GLib.IOCondition.ERR | GLib.IOCondition.HUP | GLib.IOCondition.NVAL):
                main_loop.quit()
                return GLib.SOURCE_REMOVE
            while libwl.wl_display_prepare_read(dpy) != 0:
                if libwl.wl_display_dispatch_pending(dpy) < 0:
                    main_loop.quit()
                    return GLib.SOURCE_REMOVE
            if cond & GLib.IOCondition.IN:
                if libwl.wl_display_read_events(dpy) < 0:
                    main_loop.quit()
                    return GLib.SOURCE_REMOVE
            else:
                libwl.wl_display_cancel_read(dpy)
            if libwl.wl_display_dispatch_pending(dpy) < 0:
                main_loop.quit()
                return GLib.SOURCE_REMOVE
            libwl.wl_display_flush(dpy)
            return GLib.SOURCE_CONTINUE

        wl_watch = GLib.io_add_watch(
            libwl.wl_display_get_fd(dpy),
            GLib.PRIORITY_DEFAULT,
            GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
            on_wl_io,
        )

        def check_run_marker() -> bool:
            nonlocal run_timer
            if not should_continue():
                run_timer = 0
                main_loop.quit()
                return GLib.SOURCE_REMOVE
            return GLib.SOURCE_CONTINUE

        run_timer = GLib.timeout_add(150, check_run_marker)
        sig_ids = [
            GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: main_loop.quit() or GLib.SOURCE_CONTINUE)
            for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)
        ]

        request_capture_frame()
        main_loop.run()

        if "msg" in err_box:
            emit(f"error:{err_box['msg']}")
            return True, 1
        emit("stopped")
        return True, 0
    finally:
        for s in sig_ids:
            GLib.source_remove(s)
        if run_timer:
            GLib.source_remove(run_timer)
        if pace_timer:
            GLib.source_remove(pace_timer)
        if wl_watch:
            GLib.source_remove(wl_watch)
        if pipeline is not None:
            b = pipeline.get_bus()
            if b is not None:
                b.remove_signal_watch()
            pipeline.set_state(Gst.State.NULL)
            pipeline = None
        destroy_active_frame()
        free_shm_slot()
        for entry in wl_state["outputs"]:
            if entry.get("proxy"):
                if entry["ver"] >= 3:
                    libwl.wl_proxy_marshal_flags(
                        ctypes.c_void_p(entry["proxy"]),
                        ctypes.c_uint32(0),
                        None,
                        ctypes.c_uint32(entry["ver"]),
                        ctypes.c_uint32(WL_MARSHAL_FLAG_DESTROY),
                    )
                else:
                    libwl.wl_proxy_destroy(entry["proxy"])
        if wl_state["mgr"]:
            libwl.wl_proxy_marshal_flags(
                ctypes.c_void_p(wl_state["mgr"]),
                ctypes.c_uint32(2),
                None,
                ctypes.c_uint32(wl_state["mgr_ver"]),
                ctypes.c_uint32(WL_MARSHAL_FLAG_DESTROY),
            )
        if wl_state["shm"]:
            libwl.wl_proxy_destroy(wl_state["shm"])
        libwl.wl_display_flush(dpy)
        libwl.wl_display_disconnect(dpy)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True)
    parser.add_argument("--run-file", required=True)
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--mode", choices=["portal", "region"], default="portal")
    parser.add_argument("--cursor-mode", type=int, default=2)
    parser.add_argument("--max-width", type=int, default=1920)
    parser.add_argument("--max-height", type=int, default=1080)
    parser.add_argument("--outputs-json", default="[]")
    args = parser.parse_args()

    def should_continue() -> bool:
        try:
            with open(args.run_file, "r", encoding="utf-8") as f:
                return f.read().strip() == args.session_id
        except OSError:
            return False

    try:
        outputs = json.loads(args.outputs_json)
        if not isinstance(outputs, list):
            outputs = []
    except ValueError:
        outputs = []

    emit("selecting")

    region_box: tuple[int, int, int, int] | None = None
    region_output: dict | None = None
    if args.mode == "region":
        region_output, region_box, cancelled, region_err = pick_region(outputs)
        if region_err is not None:
            emit(f"error:{region_err}")
            return 1
        if cancelled or region_box is None:
            emit("cancelled")
            return 0
        if not should_continue():
            emit("stopped")
            return 0

    GLib.set_prgname("dev.noctalia.ScreenMirrorCompanion")
    Gst.init(None)

    max_w, max_h = clamp_max_dims(args.max_width, args.max_height)
    stream_srv = PixelStreamServer(args.socket)

    try:
        # Fast path for rectangular region on wlroots compositors (Umbriel, Sway, Hyprland, etc.):
        # captures the selected output region directly via zwlr_screencopy_manager_v1 without
        # opening a second ScreenCast portal picker dialog after slurp.
        if args.mode == "region" and region_output is not None and region_box is not None:
            supported, rc = try_run_wlr_screencopy_region(
                stream_srv,
                region_output,
                region_box,
                args.cursor_mode,
                max_w,
                max_h,
                should_continue,
            )
            if supported:
                return rc

        try:
            bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        except GLib.Error as err:
            emit(f"error:{err.message}")
            return 1

        unique = bus.get_unique_name()
        if not unique:
            emit("error:D-Bus session unavailable")
            return 1

        sender = unique.lstrip(":").replace(".", "_")
        seq = 0
        session_handle: str | None = None
        closed_sub = 0
        pw_fd: int | None = None
        pipeline: Gst.Pipeline | None = None

        def close_session() -> None:
            nonlocal session_handle
            if session_handle:
                handle = session_handle
                session_handle = None
                try:
                    bus.call_sync(
                        "org.freedesktop.portal.Desktop",
                        handle,
                        "org.freedesktop.portal.Session",
                        "Close",
                        None,
                        None,
                        Gio.DBusCallFlags.NONE,
                        2000,
                        None,
                    )
                except GLib.Error:
                    pass

        def portal_request(
            method: str,
            prefix: list[GLib.Variant],
            options: dict[str, GLib.Variant],
        ) -> tuple[int, dict]:
            nonlocal seq
            seq += 1
            token = f"noctalia_mirror_{os.getpid()}_{seq}"
            expected_path = f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
            box: dict = {}
            req_loop = GLib.MainLoop()

            def on_resp(_conn, _sender, _path, _iface, _sig, sig_params):
                resp, res = sig_params.unpack()
                box["resp"] = resp
                box["res"] = res
                req_loop.quit()

            def on_abort():
                box.setdefault("resp", 1)
                req_loop.quit()
                return GLib.SOURCE_CONTINUE

            def poll_run_file():
                nonlocal timer_id
                if not should_continue():
                    timer_id = 0
                    box.setdefault("resp", 1)
                    req_loop.quit()
                    return GLib.SOURCE_REMOVE
                return GLib.SOURCE_CONTINUE

            sub_id = bus.signal_subscribe(
                "org.freedesktop.portal.Desktop",
                "org.freedesktop.portal.Request",
                "Response",
                expected_path,
                None,
                Gio.DBusSignalFlags.NONE,
                on_resp,
            )
            sig_ids = [
                GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, on_abort)
                for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)
            ]
            timer_id = GLib.timeout_add(150, poll_run_file)
            try:
                opts = dict(options)
                opts["handle_token"] = GLib.Variant("s", token)
                call_args = GLib.Variant.new_tuple(*prefix, GLib.Variant("a{sv}", opts))
                ret = bus.call_sync(
                    "org.freedesktop.portal.Desktop",
                    "/org/freedesktop/portal/desktop",
                    "org.freedesktop.portal.ScreenCast",
                    method,
                    call_args,
                    GLib.VariantType.new("(o)"),
                    Gio.DBusCallFlags.NONE,
                    -1,
                    None,
                )
                actual_path = ret.get_child_value(0).get_string()
                extra_sub = 0
                if actual_path != expected_path and "resp" not in box:
                    extra_sub = bus.signal_subscribe(
                        "org.freedesktop.portal.Desktop",
                        "org.freedesktop.portal.Request",
                        "Response",
                        actual_path,
                        None,
                        Gio.DBusSignalFlags.NONE,
                        on_resp,
                    )
                try:
                    if "resp" not in box:
                        req_loop.run()
                finally:
                    if extra_sub:
                        bus.signal_unsubscribe(extra_sub)
            finally:
                bus.signal_unsubscribe(sub_id)
                if timer_id:
                    GLib.source_remove(timer_id)
                for s in sig_ids:
                    GLib.source_remove(s)

            return box.get("resp", 2), box.get("res", {})

        tokens_path = os.path.join(args.data_dir, "restore_tokens.json")
        tokens = load_tokens(tokens_path)
        out_key = str(region_output.get("name")) if isinstance(region_output, dict) and region_output.get("name") else ""

        try:
            resp, res = portal_request(
                "CreateSession",
                [],
                {"session_handle_token": GLib.Variant("s", f"noctalia_sess_{os.getpid()}")},
            )
            if resp != 0 or "session_handle" not in res:
                emit("cancelled" if resp == 1 else "error:Failed to create ScreenCast session")
                return 0 if resp == 1 else 1

            session_handle = str(res["session_handle"])

            select_opts: dict[str, GLib.Variant] = {
                "types": GLib.Variant("u", 1 if args.mode == "region" else 3),
                "multiple": GLib.Variant("b", False),
                "cursor_mode": GLib.Variant("u", 2 if args.cursor_mode == 2 else 1),
            }
            if args.mode == "region":
                select_opts["persist_mode"] = GLib.Variant("u", 2)
                if out_key and out_key in tokens:
                    select_opts["restore_token"] = GLib.Variant("s", tokens[out_key])

            resp, _ = portal_request(
                "SelectSources",
                [GLib.Variant("o", session_handle)],
                select_opts,
            )
            if resp != 0:
                emit("cancelled" if resp == 1 else "error:Source selection failed")
                return 0 if resp == 1 else 1

            resp, res = portal_request(
                "Start",
                [GLib.Variant("o", session_handle), GLib.Variant("s", "")],
                {},
            )
            if resp != 0:
                emit("cancelled" if resp == 1 else "error:ScreenCast start failed")
                return 0 if resp == 1 else 1

            streams = res.get("streams") or []
            if not streams:
                emit("error:No ScreenCast stream returned")
                return 1

            node_id = int(streams[0][0])
            stream_props = streams[0][1] if len(streams[0]) > 1 and isinstance(streams[0][1], dict) else {}

            if args.mode == "region" and out_key and isinstance(res.get("restore_token"), str) and res["restore_token"]:
                pos = stream_props.get("position")
                if region_output is not None and (
                    not (isinstance(pos, (list, tuple)) and len(pos) == 2)
                    or (
                        int(pos[0]) == int(region_output.get("x") or 0)
                        and int(pos[1]) == int(region_output.get("y") or 0)
                    )
                ):
                    tokens[out_key] = str(res["restore_token"])
                    save_tokens(tokens_path, tokens)

            fd_ret, fd_list = bus.call_with_unix_fd_list_sync(
                "org.freedesktop.portal.Desktop",
                "/org/freedesktop/portal/desktop",
                "org.freedesktop.portal.ScreenCast",
                "OpenPipeWireRemote",
                GLib.Variant("(oa{sv})", (session_handle, {})),
                GLib.VariantType.new("(h)"),
                Gio.DBusCallFlags.NONE,
                -1,
                None,
                None,
            )
            pw_fd = fd_list.get(fd_ret.get_child_value(0).get_handle())

            crop_fractions: tuple[float, float, float, float] | None = None
            if args.mode == "region" and region_box is not None:
                rx, ry, rw, rh = region_box
                pos = stream_props.get("position")
                sz = stream_props.get("size")
                if isinstance(pos, (list, tuple)) and len(pos) == 2 and isinstance(sz, (list, tuple)) and len(sz) == 2:
                    ox, oy = int(pos[0]), int(pos[1])
                    ow, oh = int(sz[0]), int(sz[1])
                elif region_output is not None:
                    ox = int(region_output.get("x") or 0)
                    oy = int(region_output.get("y") or 0)
                    ow = int(region_output.get("width") or 1)
                    oh = int(region_output.get("height") or 1)
                else:
                    ox, oy, ow, oh = rx, ry, rw, rh

                if ow > 0 and oh > 0:
                    x0 = max(0, min(ow - 2, rx - ox))
                    y0 = max(0, min(oh - 2, ry - oy))
                    x1 = max(x0 + 2, min(ow, rx + rw - ox))
                    y1 = max(y0 + 2, min(oh, ry + rh - oy))
                    crop_fractions = (x0 / ow, y0 / oh, x1 / ow, y1 / oh)

            stream_srv.start()
            main_loop = GLib.MainLoop()

            # Negotiate PipeWire MemFd SHM (`video/x-raw`) to avoid multi-plane DCC DMA-BUF
            # modifier mismatches, stamp `pixel-aspect-ratio=1/1` via `capssetter` (since
            # `pipewiresrc` omits PAR, which otherwise overflows `videoscale` size fixation),
            # and output packed RGBA8 bounded to destination resolution for PixelStream.
            # Keep `on-disconnect=none` AND disable `do-timestamp`/`provide-clock`/`use-bufferpool`:
            # during animated tiled-window resizes, PipeWire repeatedly removes old buffers and
            # pushes `FLUSH_STOP(reset_time=TRUE)`; leaving `do-timestamp=true` or `provide-clock=true`
            # accumulates running-time skew across flushes and stalls buffer return by seconds.
            pipeline = Gst.parse_launch(
                "pipewiresrc name=src always-copy=true do-timestamp=false use-bufferpool=false provide-clock=false "
                "! video/x-raw,format={BGRx,BGRA,RGBx,RGBA} "
                "! queue max-size-buffers=1 leaky=downstream "
                "! videocrop name=crop "
                "! capssetter join=true replace=false caps=\"video/x-raw,pixel-aspect-ratio=1/1\" "
                "! videoconvert ! video/x-raw,format=RGBx,pixel-aspect-ratio=1/1 "
                "! videoscale ! videoconvert "
                f"! video/x-raw,format=RGBA,width=[1,{max_w}],height=[1,{max_h}],pixel-aspect-ratio=1/1 "
                "! appsink name=sink max-buffers=1 drop=true emit-signals=true sync=false"
            )
            src_elem = pipeline.get_by_name("src")
            src_elem.set_property("fd", pw_fd)
            src_elem.set_property("path", str(node_id))

            if crop_fractions is not None:
                fx0, fy0, fx1, fy1 = crop_fractions
                crop_elem = pipeline.get_by_name("crop")

                def on_crop_caps(_pad, info):
                    ev = info.get_event()
                    if ev.type == Gst.EventType.CAPS:
                        s = ev.parse_caps().get_structure(0)
                        ok_w, rw = s.get_int("width")
                        ok_h, rh = s.get_int("height")
                        if ok_w and ok_h and rw >= 4 and rh >= 4:
                            left = max(0, min(rw - 2, int(round(fx0 * rw))))
                            top = max(0, min(rh - 2, int(round(fy0 * rh))))
                            right = max(0, min(rw - left - 2, int(round((1.0 - fx1) * rw))))
                            bottom = max(0, min(rh - top - 2, int(round((1.0 - fy1) * rh))))
                            crop_elem.set_property("left", left)
                            crop_elem.set_property("right", right)
                            crop_elem.set_property("top", top)
                            crop_elem.set_property("bottom", bottom)
                    return Gst.PadProbeReturn.OK

                crop_elem.get_static_pad("sink").add_probe(Gst.PadProbeType.EVENT_DOWNSTREAM, on_crop_caps)

            stream_srv.attach_appsink(pipeline.get_by_name("sink"))

            err_box: dict[str, str] = {}
            gst_bus = pipeline.get_bus()
            gst_bus.add_signal_watch()

            def on_gst_msg(_bus, msg):
                if msg.type == Gst.MessageType.EOS:
                    main_loop.quit()
                elif msg.type == Gst.MessageType.ERROR:
                    err, _dbg = msg.parse_error()
                    err_box["msg"] = err.message
                    main_loop.quit()

            gst_bus.connect("message", on_gst_msg)

            closed_sub = bus.signal_subscribe(
                "org.freedesktop.portal.Desktop",
                "org.freedesktop.portal.Session",
                "Closed",
                session_handle,
                None,
                Gio.DBusSignalFlags.NONE,
                lambda *_a: main_loop.quit(),
            )

            run_timer = 0

            def check_run_marker() -> bool:
                nonlocal run_timer
                if not should_continue():
                    run_timer = 0
                    main_loop.quit()
                    return GLib.SOURCE_REMOVE
                return GLib.SOURCE_CONTINUE

            run_timer = GLib.timeout_add(150, check_run_marker)
            main_sigs = [
                GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: main_loop.quit() or GLib.SOURCE_CONTINUE)
                for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)
            ]

            try:
                if pipeline.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
                    emit("error:Failed to start GStreamer pipeline")
                    return 1
                main_loop.run()
            finally:
                if run_timer:
                    GLib.source_remove(run_timer)
                for s in main_sigs:
                    GLib.source_remove(s)

            if "msg" in err_box:
                emit(f"error:{err_box['msg']}")
                return 1
            emit("stopped")
            return 0
        except GLib.Error as err:
            emit(f"error:{err.message}")
            return 1
        finally:
            if pipeline is not None:
                b = pipeline.get_bus()
                if b is not None:
                    b.remove_signal_watch()
                pipeline.set_state(Gst.State.NULL)
                pipeline = None
            if closed_sub:
                bus.signal_unsubscribe(closed_sub)
            close_session()
            if pw_fd is not None:
                try:
                    os.close(pw_fd)
                except OSError:
                    pass
    finally:
        stream_srv.close()


if __name__ == "__main__":
    sys.exit(main())
