"""CH9141 BLE transport for the VX line protocol; no Tk calls on worker threads."""
import asyncio
import queue
import threading

from bleak import BleakClient, BleakScanner

SERVICE = "0000fff0-0000-1000-8000-00805f9b34fb"
NOTIFY = "0000fff1-0000-1000-8000-00805f9b34fb"
WRITE = "0000fff2-0000-1000-8000-00805f9b34fb"


class LineReceiver:
    def __init__(self):
        self.buffer = bytearray()

    def feed(self, data):
        self.buffer.extend(data)
        lines = []
        while b"\n" in self.buffer:
            line, _, tail = self.buffer.partition(b"\n")
            self.buffer[:] = tail
            lines.append(line.rstrip(b"\r").decode("ascii", errors="replace"))
        if len(self.buffer) > 4096:
            self.buffer.clear()
            raise ValueError("接收行超过4096字节，已清空；请检查模块串口波特率")
        return lines


def select_characteristics(services):
    """Require the actual CH9141 UART pair, never fall back to an unrelated write UUID."""
    service = next((s for s in services if s.uuid.lower() == SERVICE), None)
    if service is None:
        raise RuntimeError("未发现 FFF0 透传服务；请确认选中的是 CH9141 串口模块")
    chars = {c.uuid.lower(): c for c in service.characteristics}
    tx, rx = chars.get(NOTIFY), chars.get(WRITE)
    if tx is None or not {"notify", "indicate"}.intersection(tx.properties):
        raise RuntimeError("FFF1 不支持通知；请检查 CH9141 透传配置")
    if rx is None or not {"write", "write-without-response"}.intersection(rx.properties):
        raise RuntimeError("FFF2 不支持写入；请检查 CH9141 透传配置")
    return tx, rx, "write-without-response" not in rx.properties


class CH9141BLE:
    def __init__(self):
        self.events = queue.Queue()
        self.loop = asyncio.new_event_loop()
        self.ready = threading.Event()
        self.client = None
        self.devices = {}
        self.receiver = LineReceiver()
        self.connected = False
        self.closing = False
        self.thread = threading.Thread(target=self._run, daemon=True, name="ch9141-ble")
        self.thread.start()
        self.ready.wait(2)

    def _run(self):
        asyncio.set_event_loop(self.loop)
        self.lock = asyncio.Lock()
        self.pending_sends = 0
        self.ready.set()
        try:
            self.loop.run_forever()
        finally:
            tasks = asyncio.all_tasks(self.loop)
            for task in tasks:
                task.cancel()
            self.loop.run_until_complete(asyncio.gather(*tasks, return_exceptions=True))
            self.loop.run_until_complete(self.loop.shutdown_asyncgens())
            self.loop.close()

    def emit(self, kind, value):
        self.events.put((kind, value))

    def _submit(self, coro, done=None):
        if self.closing or not self.thread.is_alive():
            coro.close()
            return

        async def run():
            try:
                result = await coro
                if done:
                    self.emit(done, result)
            except Exception as exc:
                self.emit("error", str(exc))
                if done:
                    self.emit(done, None)
        asyncio.run_coroutine_threadsafe(run(), self.loop)

    def scan(self):
        async def run():
            if self.connected:
                raise RuntimeError("请先断开再扫描")
            found = await BleakScanner.discover(timeout=6, return_adv=True)
            self.devices = {d.address: d for d, adv in found.values()}
            rows = []
            for device, adv in found.values():
                name = adv.local_name or device.name or "未命名设备"
                likely = "ch9141" in name.lower() or SERVICE in [u.lower() for u in adv.service_uuids]
                rows.append((device.address, name, adv.rssi, likely))
            return sorted(rows, key=lambda r: (not r[3], -r[2]))
        self._submit(run(), "scan")

    def connect(self, address, pair=False):
        async def run():
            if self.client is not None:
                await self.client.disconnect()
            device = self.devices.get(address)
            if device is None:
                raise RuntimeError("请重新扫描并选择设备")
            self.receiver = LineReceiver()
            client = BleakClient(device, disconnected_callback=self._disconnected,
                                 pair=pair, timeout=60, winrt={"use_cached_services": False})
            self.client = client
            try:
                await client.connect()
                tx, self.rx, self.response = select_characteristics(client.services)
                await client.start_notify(tx, self._notification)
                self.connected = True
                self.emit("link", True)
                self.emit("info", "BLE已连接，FFF1通知/FFF2写入已启用；等待板卡STATUS回复确认UART通路")
                await self._write(":JB0\n:STATUS\n")
            except Exception:
                try:
                    await client.disconnect()
                finally:
                    self.connected = False
                raise
        self._submit(run(), "connect_done")

    def _disconnected(self, client):
        if client is self.client:
            self.connected = False
            self.receiver = LineReceiver()
            self.emit("link", False)

    def _notification(self, _sender, data):
        try:
            for line in self.receiver.feed(data):
                if line:
                    self.emit("rx", line)
        except ValueError as exc:
            self.emit("error", str(exc))

    async def _write(self, text):
        data = text.encode("ascii")
        async with self.lock:
            if not self.connected or not self.client or not self.client.is_connected:
                raise RuntimeError("蓝牙未连接")
            # 20-byte packets work at the default ATT MTU; do not assume 120-byte writes.
            for offset in range(0, len(data), 20):
                await asyncio.wait_for(self.client.write_gatt_char(
                    self.rx, data[offset:offset + 20], response=self.response), timeout=5)
                await asyncio.sleep(0.025)
            self.emit("tx", text.strip())

    def send(self, command):
        command = command.strip().lstrip(":").upper()
        if not command or len(command) > 64 or not command.isascii() or any(ord(c) < 32 for c in command):
            self.emit("error", "请输入单行ASCII指令，最多64字符")
            return

        async def run():
            if self.pending_sends >= 8 and command != "JB0":
                self.emit("error", "发送队列已满，请放慢按键")
                return
            self.pending_sends += 1
            try:
                await self._write(f":{command}\n")
            finally:
                self.pending_sends -= 1
        self._submit(run())

    async def _disconnect(self):
        try:
            if self.connected:
                await self._write(":JB0\n")
        finally:
            if self.client:
                await self.client.disconnect()
            self.connected = False
            self.emit("link", False)

    def disconnect(self):
        self._submit(self._disconnect(), "disconnect_done")

    def close(self):
        if self.closing:
            return
        self.closing = True

        async def shutdown():
            try:
                await asyncio.wait_for(self._disconnect(), timeout=3)
            finally:
                self.loop.stop()
        asyncio.run_coroutine_threadsafe(shutdown(), self.loop)

