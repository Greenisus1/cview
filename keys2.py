#!/usr/bin/env python3
"""keys - small encrypted key and password vault for the Pi.

Usage:
  python3 keys2.py                open the menu (arrow keys, Enter, q)
  python3 keys.py set NAME        save a value (hidden prompt)
  python3 keys.py get NAME        print a value
  python3 keys.py list            list names
  python3 keys.py delete NAME     remove a value
  python3 keys.py passwd          change the master password
  python3 keys.py export-file NAME PATH   write a value to a file (mode 600)

Encryption: scrypt (key derivation) + Fernet (AES-128-CBC + HMAC-SHA256)
from the "cryptography" library. Nothing is home-made.
Vault file: /root/.keyvault (mode 600). Override with KEYVAULT_FILE.
Scripts can set KEYVAULT_PASS to skip the master prompt.
"""
import base64, getpass, hashlib, json, os, sys, tempfile

try:
    from cryptography.fernet import Fernet, InvalidToken
except ImportError:
    sys.stderr.write("Missing library. Run: apt install -y python3-cryptography\n")
    sys.exit(2)

PATH = os.environ.get("KEYVAULT_FILE", os.path.join(os.path.expanduser("~"), ".keyvault"))
N, R, P = 2**15, 8, 1


def derive(pw, salt):
    k = hashlib.scrypt(pw.encode(), salt=salt, n=N, r=R, p=P, maxmem=128 * 1024 * 1024, dklen=32)
    return base64.urlsafe_b64encode(k)


def die(msg, code=1):
    sys.stderr.write(msg + "\n")
    sys.exit(code)


def ask(prompt):
    return getpass.getpass(prompt, stream=sys.stderr)


def master(confirm=False):
    pw = os.environ.get("KEYVAULT_PASS")
    if pw:
        return pw
    pw = ask("Master password: ")
    if confirm:
        if len(pw) < 8:
            die("Use at least 8 characters.")
        if ask("Repeat master password: ") != pw:
            die("Passwords did not match.")
    return pw


def write(data, pw, salt=None):
    salt = salt or os.urandom(16)
    token = Fernet(derive(pw, salt)).encrypt(json.dumps(data).encode())
    blob = json.dumps({"v": 1, "salt": base64.b64encode(salt).decode(), "data": token.decode()})
    d = os.path.dirname(os.path.abspath(PATH))
    fd, tmp = tempfile.mkstemp(dir=d)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(blob)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, PATH)


def load(pw=None):
    if not os.path.exists(PATH):
        pw = pw or master(confirm=True)
        write({}, pw)
        sys.stderr.write("New vault created at %s\n" % PATH)
        return {}, pw
    pw = pw or master()
    try:
        blob = json.load(open(PATH))
        salt = base64.b64decode(blob["salt"])
        data = json.loads(Fernet(derive(pw, salt)).decrypt(blob["data"].encode()))
    except InvalidToken:
        die("Wrong master password.")
    except (ValueError, KeyError):
        die("Vault file is damaged.")
    return data, pw


def menu():
    import curses

    def run(scr):
        curses.curs_set(0)
        scr.keypad(True)

        def msg(lines, wait=True):
            scr.erase()
            h, w = scr.getmaxyx()
            for i, l in enumerate(lines[: h - 1]):
                scr.addnstr(i + 1, 2, l, w - 4)
            if wait:
                scr.addnstr(min(len(lines) + 2, h - 1), 2, "Press any key", w - 4)
                scr.refresh()
                scr.getch()
            scr.refresh()

        def prompt(label, hidden=True):
            curses.curs_set(1)
            buf = ""
            while True:
                scr.erase()
                h, w = scr.getmaxyx()
                scr.addnstr(1, 2, label, w - 4)
                scr.addnstr(3, 2, ("*" * len(buf)) if hidden else buf, w - 4)
                scr.addnstr(5, 2, "Enter = ok, Esc = cancel", w - 4)
                scr.move(3, min(2 + len(buf), w - 2))
                scr.refresh()
                k = scr.get_wch()
                if k in ("\n", "\r"):
                    curses.curs_set(0)
                    return buf
                if k == "\x1b":
                    curses.curs_set(0)
                    return None
                if k in ("\x7f", "\b", curses.KEY_BACKSPACE):
                    buf = buf[:-1]
                elif isinstance(k, str) and k.isprintable():
                    buf += k

        def choose(title, items):
            if not items:
                return -1
            i = 0
            while True:
                scr.erase()
                h, w = scr.getmaxyx()
                scr.addnstr(1, 2, title, w - 4, curses.A_BOLD)
                top = max(0, i - (h - 6))
                for n, it in enumerate(items[top: top + h - 5]):
                    attr = curses.A_REVERSE if top + n == i else 0
                    scr.addnstr(3 + n, 4, " " + it + " ", w - 6, attr)
                scr.refresh()
                k = scr.getch()
                if k == curses.KEY_UP:
                    i = (i - 1) % len(items)
                elif k == curses.KEY_DOWN:
                    i = (i + 1) % len(items)
                elif k in (10, 13, curses.KEY_ENTER):
                    return i
                elif k in (27, ord("q")):
                    return -1

        # unlock
        data = pw = None
        new = not os.path.exists(PATH)
        for _ in range(3):
            pw = prompt("Create master password (8+ characters)" if new else "Master password")
            if pw is None:
                return
            if new:
                if len(pw) < 8:
                    msg(["Use at least 8 characters."])
                    continue
                if prompt("Repeat master password") != pw:
                    msg(["Passwords did not match."])
                    continue
                write({}, pw)
                data = {}
                break
            try:
                blob = json.load(open(PATH))
                salt = base64.b64decode(blob["salt"])
                data = json.loads(Fernet(derive(pw, salt)).decrypt(blob["data"].encode()))
                break
            except InvalidToken:
                msg(["Wrong master password."])
            except (ValueError, KeyError):
                msg(["Vault file is damaged."])
                return
        if data is None:
            return

        while True:
            c = choose("Key vault  (arrows, Enter, q to quit)",
                       ["View a key", "Add or change a key", "Delete a key",
                        "Change master password", "Quit"])
            if c in (-1, 4):
                return
            names = sorted(data)
            if c == 0:
                j = choose("View which key?", names) if names else msg(["Vault is empty."]) or -1
                if j >= 0:
                    msg(["Name: " + names[j], "Value: " + data[names[j]], "",
                         "Screen clears when you press a key."])
            elif c == 1:
                n = prompt("Name for the key (example: cloudflare)", hidden=False)
                if n and n.strip():
                    v = prompt("Value for " + n.strip())
                    if v:
                        data[n.strip()] = v
                        write(data, pw)
                        msg(["Saved " + n.strip()])
            elif c == 2:
                j = choose("Delete which key?", names) if names else msg(["Vault is empty."]) or -1
                if j >= 0:
                    a = choose("Really delete " + names[j] + "?", ["No, keep it", "Yes, delete"])
                    if a == 1:
                        del data[names[j]]
                        write(data, pw)
                        msg(["Deleted " + names[j]])
            elif c == 3:
                p1 = prompt("New master password (8+ characters)")
                if p1 is None:
                    continue
                if len(p1) < 8:
                    msg(["Use at least 8 characters."])
                elif prompt("Repeat new master password") != p1:
                    msg(["Passwords did not match."])
                else:
                    pw = p1
                    write(data, pw)
                    msg(["Master password changed."])

    curses.wrapper(run)


def main(a):
    if not a:
        return menu()
    cmd = a[0]
    if cmd == "set" and len(a) == 2:
        data, pw = load()
        v = ask("Value for %s: " % a[1])
        if not v:
            die("Empty, nothing saved.")
        data[a[1]] = v
        write(data, pw)
        sys.stderr.write("Saved %s\n" % a[1])
    elif cmd == "get" and len(a) == 2:
        data, _ = load()
        if a[1] not in data:
            die("No such name: %s" % a[1], 3)
        sys.stdout.write(data[a[1]] + ("\n" if sys.stdout.isatty() else ""))
    elif cmd == "list" and len(a) == 1:
        data, _ = load()
        for k in sorted(data):
            print(k)
    elif cmd == "delete" and len(a) == 2:
        data, pw = load()
        if a[1] not in data:
            die("No such name: %s" % a[1], 3)
        del data[a[1]]
        write(data, pw)
        sys.stderr.write("Deleted %s\n" % a[1])
    elif cmd == "passwd" and len(a) == 1:
        data, _ = load()
        os.environ.pop("KEYVAULT_PASS", None)
        write(data, master(confirm=True))
        sys.stderr.write("Master password changed.\n")
    elif cmd == "export-file" and len(a) == 3:
        data, _ = load()
        if a[1] not in data:
            die("No such name: %s" % a[1], 3)
        fd = os.open(a[2], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.write(fd, data[a[1]].encode())
        os.close(fd)
        sys.stderr.write("Wrote %s (mode 600)\n" % a[2])
    else:
        die(__doc__, 1)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except EOFError:
        die("\nNo input.", 130)
    except KeyboardInterrupt:
        die("\nCancelled.", 130)
