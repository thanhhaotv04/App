"""Exercise a connected NavRide board over HTTP and BLE, then restore Wi-Fi.

Run with Python containing bleak and pyserial:
  python tools/smoke_test.py --ip 192.168.1.55 --serial /dev/ttyACM0
This sends temporary test content and switches the board's connection mode.
Serial DISPLAY messages verify the draw path, not the physical TFT pixels.
"""
import argparse
import asyncio
import json
import threading
import time
import urllib.error
import urllib.request

import serial
from bleak import BleakClient, BleakScanner

SERVICE = "7e6d0001-5b1a-4d8f-9a2c-320001000001"
COMMAND = "7e6d0002-5b1a-4d8f-9a2c-320001000002"
STATUS = "7e6d0003-5b1a-4d8f-9a2c-320001000003"


async def main(args):
    port = serial.Serial(port=None, baudrate=115200, timeout=.2)
    port.port, port.rts, port.dtr = args.serial, False, True
    port.open()
    lines, stopped = [], threading.Event()

    def read_serial():
        while not stopped.is_set():
            line = port.readline().decode(errors="replace").strip()
            if line:
                lines.append(line)
                print("SERIAL", line, flush=True)

    reader = threading.Thread(target=read_serial, daemon=True)
    reader.start()

    def http(path, payload=None, expected=200):
        body = None if payload is None else json.dumps(payload).encode()
        request = urllib.request.Request(f"http://{args.ip}{path}", data=body,
                                         headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=4) as response:
                status, result = response.status, json.load(response)
        except urllib.error.HTTPError as error:
            status, result = error.code, json.load(error)
        assert status == expected, (status, result)
        return result

    def command(**fields):
        return {"apiVersion": 1, "timestamp": int(time.time()), **fields}

    try:
        health = http("/api/health")
        assert health["firmware"] == "1.3.3" and health["mode"] == "wifi", health
        print("HEALTH", health, flush=True)
        assert http("/api/command", command(command="push_notification", title="Road test",
                    body="Check mirrors before riding"))["ok"]
        http("/api/command", command(command="unknown"), expected=400)
        http("/api/command", command(command="push_notification", body="x" * 513), expected=400)
        for distance in [2000, 1999, 1000, 999, 250]:
            assert http("/api/command", command(command="navigation", maneuver="left",
                        distance_m=distance, street="Nguyễn Huệ"))["ok"]
            await asyncio.sleep(.15)
        assert http("/api/command", command(command="set_mode", mode="bluetooth"))["ok"]
        await asyncio.sleep(1)
        device = await BleakScanner.find_device_by_filter(
            lambda device, advert: device.address.upper() == args.ble.upper()
            and SERVICE in advert.service_uuids, timeout=12,
        )
        assert device is not None, "Board not advertising BLE"
        replies = asyncio.Queue()
        async with BleakClient(device, timeout=15) as client:
            await client.start_notify(STATUS, lambda _, value: replies.put_nowait(bytes(value).decode()))
            request_id = 12340

            async def send(kind, ack, **fields):
                nonlocal request_id
                request_id += 1
                payload = json.dumps(command(command=kind, requestId=request_id, **fields),
                                     ensure_ascii=False, separators=(",", ":")).encode()
                assert len(payload) <= 180, len(payload)
                await client.write_gatt_char(COMMAND, payload, response=True)
                expected = f"ok:{ack}:{request_id}"
                while True:
                    reply = await asyncio.wait_for(replies.get(), timeout=5)
                    assert not reply.startswith("error:"), reply
                    if reply == expected:
                        print("BLE ACK", reply, "bytes", len(payload), flush=True)
                        break

            try:
                await send("ping", "ping")
                await send("push_notification", "popup", title='Turn "test"', body="Nguyễn Huệ → 250 m")
                await send("push_task", "popup", title="Check fuel", body="Pending")
                for maneuver in ["left", "right", "u_turn", "straight", "arrive"]:
                    await send("navigation", "navigation", maneuver=maneuver, distance_m=250, street="Nguyen Hue")
                    await asyncio.sleep(.15)
                await client.write_gatt_char(COMMAND, b'{"apiVersion":2,"command":"ping"}', response=True)
                assert await asyncio.wait_for(replies.get(), 5) == "error:api_version"
                await send("clear_popup", "clear")
            finally:
                await send("set_mode", "mode", mode="wifi")
        for _ in range(15):
            await asyncio.sleep(1)
            try:
                health = http("/api/health")
                if health["mode"] == "wifi":
                    break
            except (OSError, urllib.error.URLError):
                continue
        assert health["mode"] == "wifi", "Wi-Fi was not restored"
        joined = "\n".join(lines)
        for expected in ["2.00 km arrow=straight blink=no", "1.99 km arrow=left blink=no",
                         "1.00 km arrow=left blink=no", "999 m arrow=left blink=yes",
                         "DISPLAY: popup", "navigation u_turn", "navigation right"]:
            assert expected in joined, f"Missing draw evidence: {expected}"
        print("PASS: HTTP, BLE request-ID ACKs, text rendering paths and distance thresholds; Wi-Fi restored.")
    finally:
        stopped.set()
        reader.join(timeout=1)
        port.dtr, port.rts = False, False
        port.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ip", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--ble", default="14:C1:9F:27:03:45")
    asyncio.run(main(parser.parse_args()))
