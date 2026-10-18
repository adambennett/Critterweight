#!/usr/bin/env python3
"""Store/check the Breeze API key in the current Windows user's Credential Manager."""

import argparse
import ctypes
import getpass
import re
import sys
from ctypes import wintypes


TARGET = "ThirdAgeModern/BreezeBlue/API"
GENERIC = 1
PERSIST_LOCAL_MACHINE = 2


def validate_key(key):
    """Reject paste keystrokes and malformed secrets without echoing them."""
    key = key.strip()
    if not re.fullmatch(r"brz_[A-Za-z0-9_-]+", key):
        raise ValueError(
            "The Breeze key is malformed. Copy the actual brz_ API key, then run "
            "configure_key.py set --clipboard. Ctrl+V at a hidden Windows "
            "console prompt can enter a control character instead of pasting.")
    if len(key.encode("utf-8")) > 2560:
        raise ValueError("The key exceeds Windows Credential Manager's size limit.")
    return key


def read_clipboard_key():
    """Read only on explicit --clipboard invocation; never print clipboard data."""
    if sys.platform != "win32":
        raise RuntimeError("Clipboard setup is available only on Windows.")
    user32 = ctypes.WinDLL("User32.dll", use_last_error=True)
    kernel32 = ctypes.WinDLL("Kernel32.dll", use_last_error=True)
    user32.OpenClipboard.argtypes = [wintypes.HWND]
    user32.OpenClipboard.restype = wintypes.BOOL
    user32.GetClipboardData.argtypes = [wintypes.UINT]
    user32.GetClipboardData.restype = wintypes.HANDLE
    user32.CloseClipboard.argtypes = []
    user32.CloseClipboard.restype = wintypes.BOOL
    kernel32.GlobalLock.argtypes = [wintypes.HANDLE]
    kernel32.GlobalLock.restype = ctypes.c_void_p
    kernel32.GlobalUnlock.argtypes = [wintypes.HANDLE]
    kernel32.GlobalUnlock.restype = wintypes.BOOL
    if not user32.OpenClipboard(None):
        raise RuntimeError("Cannot open the clipboard. Close clipboard tools and try again.")
    try:
        handle = user32.GetClipboardData(13)  # CF_UNICODETEXT
        if not handle:
            raise ValueError("The clipboard contains no text. Copy the Breeze API key first.")
        pointer = kernel32.GlobalLock(handle)
        if not pointer:
            raise RuntimeError("Cannot read clipboard text.")
        try:
            return validate_key(ctypes.wstring_at(pointer))
        finally:
            kernel32.GlobalUnlock(handle)
    finally:
        user32.CloseClipboard()


class FILETIME(ctypes.Structure):
    _fields_ = [("dwLowDateTime", wintypes.DWORD), ("dwHighDateTime", wintypes.DWORD)]


class CREDENTIAL(ctypes.Structure):
    _fields_ = [
        ("Flags", wintypes.DWORD),
        ("Type", wintypes.DWORD),
        ("TargetName", wintypes.LPCWSTR),
        ("Comment", wintypes.LPWSTR),
        ("LastWritten", FILETIME),
        ("CredentialBlobSize", wintypes.DWORD),
        ("CredentialBlob", ctypes.POINTER(ctypes.c_ubyte)),
        ("Persist", wintypes.DWORD),
        ("AttributeCount", wintypes.DWORD),
        ("Attributes", ctypes.c_void_p),
        ("TargetAlias", wintypes.LPWSTR),
        ("UserName", wintypes.LPCWSTR),
    ]


def _api():
    if sys.platform != "win32":
        raise RuntimeError("Credential Manager storage is available only on Windows.")
    advapi = ctypes.WinDLL("Advapi32.dll", use_last_error=True)
    advapi.CredWriteW.argtypes = [ctypes.POINTER(CREDENTIAL), wintypes.DWORD]
    advapi.CredWriteW.restype = wintypes.BOOL
    advapi.CredReadW.argtypes = [
        wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
        ctypes.POINTER(ctypes.POINTER(CREDENTIAL)),
    ]
    advapi.CredReadW.restype = wintypes.BOOL
    advapi.CredFree.argtypes = [ctypes.c_void_p]
    advapi.CredFree.restype = None
    return advapi


def store_key(key):
    key = validate_key(key)
    raw = key.encode("utf-8")
    if not raw or len(raw) > 2560:
        raise ValueError("The key is empty or exceeds Windows Credential Manager's size limit.")
    blob = (ctypes.c_ubyte * len(raw)).from_buffer_copy(raw)
    cred = CREDENTIAL()
    cred.Type = GENERIC
    cred.TargetName = TARGET
    cred.CredentialBlobSize = len(raw)
    cred.CredentialBlob = ctypes.cast(blob, ctypes.POINTER(ctypes.c_ubyte))
    cred.Persist = PERSIST_LOCAL_MACHINE
    cred.UserName = "BREEZE_API_KEY"
    if not _api().CredWriteW(ctypes.byref(cred), 0):
        raise ctypes.WinError(ctypes.get_last_error())
    if load_key() != key:
        raise RuntimeError("Credential verification failed after saving.")


def load_key():
    advapi = _api()
    result = ctypes.POINTER(CREDENTIAL)()
    if not advapi.CredReadW(TARGET, GENERIC, 0, ctypes.byref(result)):
        code = ctypes.get_last_error()
        if code == 1168:  # ERROR_NOT_FOUND
            return None
        raise ctypes.WinError(code)
    try:
        value = ctypes.string_at(result.contents.CredentialBlob,
                                 result.contents.CredentialBlobSize).decode("utf-8")
        return validate_key(value)
    finally:
        advapi.CredFree(result)


def has_key():
    return load_key() is not None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("set", "status"))
    parser.add_argument("--clipboard", action="store_true",
                        help="Windows: read the copied key directly, avoiding terminal paste issues.")
    args = parser.parse_args()
    try:
        if args.action == "status":
            message = "A Breeze key is saved in this Windows user's Credential Manager." if has_key() else "No Breeze key is saved in this Windows user's Credential Manager."
            print(message)
            return 0

        if args.clipboard:
            key = read_clipboard_key()
        else:
            key = validate_key(getpass.getpass("Breeze API key (input hidden): "))
            confirmation = validate_key(getpass.getpass("Re-enter Breeze API key: "))
            if key != confirmation:
                print("The entries differed; nothing was saved.", file=sys.stderr)
                return 2
        store_key(key)
        print("Breeze API key saved to this Windows user's Credential Manager.")
        return 0
    except (OSError, RuntimeError, ValueError) as exc:
        print("Credential Manager operation failed: {}".format(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
