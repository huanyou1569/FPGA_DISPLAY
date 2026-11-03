"""Host-side BLE regression tests; no physical Bluetooth access."""
import asyncio
import unittest
from types import SimpleNamespace as NS
from unittest.mock import AsyncMock

from ch9141_ble import CH9141BLE, LineReceiver, select_characteristics, SERVICE, NOTIFY, WRITE


def services(properties):
    return [NS(uuid=SERVICE, characteristics=[
        NS(uuid=NOTIFY, properties=["notify"]),
        NS(uuid=WRITE, properties=properties)])]


class ProtocolTests(unittest.TestCase):
    def test_split_and_coalesced_notifications(self):
        receiver = LineReceiver()
        self.assertEqual(receiver.feed(b"RPM:0 MO"), [])
        self.assertEqual(receiver.feed(b"DE:BRUSH\r\nOK\nER"), ["RPM:0 MODE:BRUSH", "OK"])
        self.assertEqual(receiver.feed(b"R:MODE\r\r\n"), ["ERR:MODE"])

    def test_oversized_notification_recovers(self):
        receiver = LineReceiver()
        with self.assertRaises(ValueError):
            receiver.feed(b"x" * 4097)
        self.assertEqual(receiver.feed(b"OK\n"), ["OK"])

    def test_selects_supported_write_mode(self):
        self.assertFalse(select_characteristics(services(["write-without-response"]))[2])
        self.assertTrue(select_characteristics(services(["write"]))[2])

    def test_rejects_missing_or_incompatible_uart(self):
        with self.assertRaises(RuntimeError):
            select_characteristics([])
        with self.assertRaises(RuntimeError):
            select_characteristics(services(["read"]))
        missing_notify = services(["write"])
        missing_notify[0].characteristics[0].properties = ["read"]
        with self.assertRaises(RuntimeError):
            select_characteristics(missing_notify)


class SendTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.ble = CH9141BLE.__new__(CH9141BLE)
        self.ble.lock = asyncio.Lock()
        self.ble.connected = True
        self.ble.client = NS(is_connected=True, write_gatt_char=AsyncMock())
        self.ble.rx = "actual-characteristic"
        self.ble.response = True
        self.events = []
        self.ble.emit = lambda *e: self.events.append(e)

    async def test_long_commands_never_interleave(self):
        a = ":" + "A" * 35 + "\n"
        b = ":STATUS\n"
        await asyncio.gather(self.ble._write(a), self.ble._write(b))
        calls = self.ble.client.write_gatt_char.await_args_list
        self.assertTrue(all(len(c.args[1]) <= 20 for c in calls))
        self.assertEqual(b"".join(c.args[1] for c in calls), (a + b).encode())
        self.assertTrue(all(c.kwargs["response"] for c in calls))

    async def test_disconnected_write_is_not_reported_as_success(self):
        self.ble.client.is_connected = False
        with self.assertRaises(RuntimeError):
            await self.ble._write(":JP\n")
        self.assertEqual(self.events, [])

    async def test_transport_failure_propagates(self):
        self.ble.client.write_gatt_char.side_effect = OSError("link lost")
        with self.assertRaises(OSError):
            await self.ble._write(":STATUS\n")
        self.assertEqual(self.events, [])


if __name__ == "__main__":
    unittest.main()
