# usage: xwin.py close|focus <window title>   (exact title, on $DISPLAY)
#   close: sends WM_DELETE_WINDOW, what a window manager's close button does
#   focus: raises the window and gives it keyboard focus (there is no window manager on the private Xvfb display)
import ctypes, ctypes.util, os, sys
x = ctypes.CDLL(ctypes.util.find_library("X11") or "libX11.so.6")
x.XOpenDisplay.restype = ctypes.c_void_p
x.XInternAtom.restype = ctypes.c_ulong
x.XDefaultRootWindow.restype = ctypes.c_ulong
d = x.XOpenDisplay(None)
root = x.XDefaultRootWindow(ctypes.c_void_p(d))
def children(w):
    r, p, ch, n = ctypes.c_ulong(), ctypes.c_ulong(), ctypes.POINTER(ctypes.c_ulong)(), ctypes.c_uint()
    x.XQueryTree(ctypes.c_void_p(d), ctypes.c_ulong(w), ctypes.byref(r), ctypes.byref(p), ctypes.byref(ch), ctypes.byref(n))
    return [ch[i] for i in range(n.value)]
def name(w):
    s = ctypes.c_char_p()
    x.XFetchName(ctypes.c_void_p(d), ctypes.c_ulong(w), ctypes.byref(s))
    return s.value.decode() if s.value else ""
class CM(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int), ("display", ctypes.c_void_p), ("window", ctypes.c_ulong), ("message_type", ctypes.c_ulong), ("format", ctypes.c_int), ("l", ctypes.c_long * 5)]
class EV(ctypes.Union):
    _fields_ = [("cm", CM), ("pad", ctypes.c_long * 24)]
wm = x.XInternAtom(ctypes.c_void_p(d), b"WM_PROTOCOLS", 0)
dw = x.XInternAtom(ctypes.c_void_p(d), b"WM_DELETE_WINDOW", 0)
for w in children(root):
    if name(w) == sys.argv[2]:
        if sys.argv[1] == "focus":
            x.XRaiseWindow(ctypes.c_void_p(d), ctypes.c_ulong(w))
            x.XSetInputFocus(ctypes.c_void_p(d), ctypes.c_ulong(w), 2, 0)
            x.XSync(ctypes.c_void_p(d), 0); print("focused", hex(w)); break
        e = EV(); e.cm.type = 33; e.cm.window = w; e.cm.message_type = wm; e.cm.format = 32; e.cm.l[0] = dw; e.cm.l[1] = 0
        x.XSendEvent(ctypes.c_void_p(d), ctypes.c_ulong(w), 0, 0, ctypes.byref(e))
        x.XFlush(ctypes.c_void_p(d)); print("sent to", hex(w)); break
else: print("no window"); sys.exit(1)
