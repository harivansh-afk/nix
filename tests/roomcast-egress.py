import argparse
import contextlib
import errno
import os
import pwd
import socket
import subprocess
import time


def run(*args):
    subprocess.run(args, check=True)


@contextlib.contextmanager
def socket_as(uid, family=socket.AF_INET, kind=socket.SOCK_STREAM):
    os.seteuid(uid)
    try:
        with socket.socket(family, kind) as sock:
            sock.settimeout(0.5)
            yield sock
    finally:
        os.seteuid(0)


def tcp_policy(uid, address, port, expected):
    family = socket.AF_INET6 if ":" in address else socket.AF_INET
    with socket.socket(family) as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((address, port))
        server.listen()
        server.settimeout(0.5)
        result = "connected"
        with socket_as(uid, family) as client:
            try:
                client.connect(server.getsockname())
                client.sendall(b"ok")
            except TimeoutError:
                result = "dropped"
            except ConnectionRefusedError:
                result = "rejected"
        assert result == expected, (uid, address, port, expected, result)
        if result == "connected":
            with server.accept()[0] as peer:
                assert peer.recv(2) == b"ok"


def closed_port(family, address):
    with socket.socket(family) as reservation:
        reservation.bind((address, 0))
        target = reservation.getsockname()
    with socket_as(args.owner_uid, family) as client:
        result = client.connect_ex(target)
    assert result == errno.ECONNREFUSED, (target, result)


def socket_states(family, port):
    path = "/proc/net/tcp6" if family == socket.AF_INET6 else "/proc/net/tcp"
    with open(path) as entries:
        return {
            fields[3]
            for line in list(entries)[1:]
            if (fields := line.split()) and int(fields[1].split(":")[1], 16) == port
        }


def teardown(family, address):
    with socket.socket(family) as server, socket.socket(family) as client:
        server.bind((address, 0))
        server.listen()
        server_port = server.getsockname()[1]
        client.connect(server.getsockname())
        client_port = client.getsockname()[1]
        peer, _ = server.accept()
        peer.close()
        client.settimeout(0.5)
        assert client.recv(1) == b""
    deadline = time.monotonic() + 1
    while socket_states(family, client_port) and time.monotonic() < deadline:
        time.sleep(0.01)
    assert "06" in socket_states(family, server_port), "server never entered TIME_WAIT"
    assert not socket_states(family, client_port), (
        "client stuck waiting for ownerless FIN acknowledgment"
    )


def dns_udp():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as resolver:
        resolver.bind(("127.0.0.53", 53))
        resolver.settimeout(0.5)
        with socket_as(roomcast_uid, kind=socket.SOCK_DGRAM) as client:
            client.sendto(b"dns", resolver.getsockname())
        assert resolver.recv(3) == b"dns"


parser = argparse.ArgumentParser()
parser.add_argument("--rules", required=True)
parser.add_argument("--owner-uid", required=True, type=int)
parser.add_argument("--mcp-port", required=True, type=int)
args = parser.parse_args()
assert os.geteuid() == 0
os.unshare(os.CLONE_NEWNET)
roomcast_uid = pwd.getpwnam("roomcast").pw_uid
guest_uid = 12345
assert guest_uid not in (0, roomcast_uid, args.owner_uid)
run("ip", "link", "set", "lo", "up")
for address in (
    "10.23.45.67/32",
    "93.184.216.34/32",
    "2001:db8::123/128",
    "fd00::123/128",
):
    flags = ["nodad"] if ":" in address else []
    run("ip", "address", "add", address, "dev", "lo", *flags)
run("nft", "-f", args.rules)

tests = [
    (
        "ownerless IPv4 closed-port reset",
        lambda: closed_port(socket.AF_INET, "127.0.0.1"),
    ),
    ("ownerless IPv6 closed-port reset", lambda: closed_port(socket.AF_INET6, "::1")),
    (
        "ownerless IPv4 TIME_WAIT acknowledgment",
        lambda: teardown(socket.AF_INET, "127.0.0.1"),
    ),
    (
        "ownerless IPv6 TIME_WAIT acknowledgment",
        lambda: teardown(socket.AF_INET6, "::1"),
    ),
    (
        "ordinary user private TCP",
        lambda: tcp_policy(args.owner_uid, "10.23.45.67", 28791, "connected"),
    ),
    (
        "Roomcast private IPv4 TCP denied",
        lambda: tcp_policy(roomcast_uid, "10.23.45.67", 28792, "dropped"),
    ),
    (
        "Roomcast loopback TCP denied",
        lambda: tcp_policy(roomcast_uid, "127.0.0.1", 28793, "dropped"),
    ),
    (
        "Roomcast private IPv6 TCP denied",
        lambda: tcp_policy(roomcast_uid, "fd00::123", 28794, "dropped"),
    ),
    (
        "Roomcast public IPv4 HTTPS allowed",
        lambda: tcp_policy(roomcast_uid, "93.184.216.34", 443, "connected"),
    ),
    (
        "Roomcast public IPv6 HTTPS allowed",
        lambda: tcp_policy(roomcast_uid, "2001:db8::123", 443, "connected"),
    ),
    (
        "Roomcast public HTTP denied",
        lambda: tcp_policy(roomcast_uid, "93.184.216.34", 80, "dropped"),
    ),
    (
        "Roomcast TCP DNS allowed",
        lambda: tcp_policy(roomcast_uid, "127.0.0.53", 53, "connected"),
    ),
    ("Roomcast UDP DNS allowed", dns_udp),
    (
        "MCP root allowed",
        lambda: tcp_policy(0, "127.0.0.1", args.mcp_port, "connected"),
    ),
    (
        "MCP owner allowed",
        lambda: tcp_policy(args.owner_uid, "127.0.0.1", args.mcp_port, "connected"),
    ),
    (
        "MCP guest rejected",
        lambda: tcp_policy(guest_uid, "127.0.0.1", args.mcp_port, "rejected"),
    ),
    (
        "MCP Roomcast rejected",
        lambda: tcp_policy(roomcast_uid, "127.0.0.1", args.mcp_port, "rejected"),
    ),
]
failures = []
for name, test in tests:
    try:
        test()
        print(f"PASS: {name}", flush=True)
    except Exception as error:
        failures.append(name)
        print(f"FAIL: {name}: {error!r}", flush=True)
assert not failures, failures
