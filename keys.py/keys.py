#!/usr/bin/env python3
"""keys - small encrypted key and password vault for the Pi.

Usage:
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


def main(a):
    if not a:
        die(__doc__, 0)
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
