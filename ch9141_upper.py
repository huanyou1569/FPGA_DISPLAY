"""VX-Display PYNQ-Z2 brush controller, adapted from the original upper_computer protocol."""
import json
import os
from pathlib import Path
import queue
import time
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext

from ch9141_ble import CH9141BLE

SETTINGS = Path(__file__).with_name(".ch9141_settings.json")


class App:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("VX-Display · CH9141 画笔 / 贪吃蛇 / 3D方块 · 15转/秒 · 120面/转")
        self.root.geometry("880x900")
        self.root.minsize(740, 650)
        self.ble = CH9141BLE()
        self.rows = []
        self.busy = False
        self.shift = False
        self.closed = False
        self.angle = 0
        self.mode = "DEMO"
        self.last_key = {}
        self.pressed = set()
        self.query_time = None
        self.last_query = 0
        try:
            self.saved = json.loads(SETTINGS.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            self.saved = {}
        self.status = tk.StringVar(value="未连接")
        self.board = tk.StringVar(value="板卡状态：尚未收到蓝牙UART回复")
        self.rotation = tk.StringVar(value="同步反馈：等待新固件的 SYNC 状态")
        self.pair = tk.BooleanVar(value=False)
        self.auto = tk.BooleanVar(value=True)
        self.build_ui()
        self.root.bind("<KeyPress>", self.key)
        self.root.bind("<KeyRelease>", self.key_release)
        self.root.bind("<KeyRelease-Shift_L>", self.release_shift)
        self.root.bind("<KeyRelease-Shift_R>", self.release_shift)
        self.root.bind("<FocusOut>", self.focus_out)
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        self.log("提示", "先扫描并连接CH9141；需要0000配对码时，使用Windows配对窗口。串口端须为115200 8N1。")
        self.poll()

    def build_ui(self):
        conn = ttk.LabelFrame(self.root, text="CH9141 BLE连接", padding=10)
        conn.pack(fill="x", padx=12, pady=8)
        row = ttk.Frame(conn)
        row.pack(fill="x")
        self.scan_btn = ttk.Button(row, text="扫描6秒", command=self.scan)
        self.scan_btn.pack(side="left")
        self.combo = ttk.Combobox(row, state="readonly", width=47)
        self.combo.pack(side="left", fill="x", expand=True, padx=6)
        self.connect_btn = ttk.Button(row, text="连接", command=self.connect)
        self.connect_btn.pack(side="left")
        self.disconnect_btn = ttk.Button(row, text="断开", command=self.disconnect)
        self.disconnect_btn.pack(side="left", padx=4)
        row = ttk.Frame(conn)
        row.pack(fill="x", pady=6)
        ttk.Checkbutton(row, text="连接时请求系统配对（需要PIN时勾选）", variable=self.pair).pack(side="left")
        ttk.Button(row, text="Windows蓝牙设置", command=self.open_settings).pack(side="right")
        ttk.Label(conn, textvariable=self.status).pack(anchor="w")
        ttk.Label(conn, text="配对码0000由Windows窗口处理；无需选择COM口。设备名可被修改，扫描会保留所有设备。").pack(anchor="w")
        panel = ttk.LabelFrame(self.root, text="画笔控制 · 按键与原工程兼容", padding=10)
        panel.pack(fill="x", padx=12, pady=4)
        buttons = [("进入画笔 B", "BRUSH"), ("返回演示 E", "DEMO"),
                   ("落笔/抬笔 P", "JP"), ("换色 K", "JK"), ("清空 C", "CLEAR")]
        for i, (label, command) in enumerate(buttons):
            ttk.Button(panel, text=label, command=lambda c=command: self.send(c)).grid(row=0, column=i, padx=3, pady=5, sticky="ew")
            panel.columnconfigure(i, weight=1)
        for col, label, command in [(0, "左 A", "JL"), (1, "前 W", "JU"), (2, "后 S", "JD"), (3, "右 D", "JR")]:
            ttk.Button(panel, text=label, command=lambda c=command: self.send(c)).grid(row=1, column=col, padx=3, pady=5, sticky="ew")
        ttk.Button(panel, text="上升 Shift+W", command=lambda: self.vertical("JU")).grid(row=2, column=1, pady=5)
        ttk.Button(panel, text="下降 Shift+S", command=lambda: self.vertical("JD")).grid(row=2, column=2, pady=5)
        ttk.Button(panel, text="视角 -90° [", command=lambda: self.change_angle(-25)).grid(row=2, column=0)
        ttk.Button(panel, text="视角 +90° ]", command=lambda: self.change_angle(25)).grid(row=2, column=3)
        ttk.Button(panel, text="贪吃蛇 G", command=lambda: self.send("SNAKE")).grid(row=1, column=4, padx=3, pady=5, sticky="ew")
        ttk.Button(panel, text="新游戏 N", command=lambda: self.send("JG")).grid(row=2, column=4, padx=3, pady=5, sticky="ew")
        ttk.Label(panel, text="BTN2：演示→画笔→贪吃蛇→3D方块。蛇：A/D左右转，W/S上/下，N重开，E退出。").grid(row=3, column=0, columnspan=5, pady=6)
        blocks=ttk.LabelFrame(self.root,text="3D俄罗斯方块 · 需配套tetris固件",padding=6)
        blocks.pack(fill="x",padx=12,pady=4)
        actions=[("进入 T","TETRIS"),("重开 N","TG"),("暂停 P","TP"),("硬降 空格","TH"),("软降 ↓","TD"),
                 ("X+ Q","TX+"),("X− Z","TX-"),("Y+ R","TY+"),("Y− F","TY-"),("Z+ C","TZ+"),("Z− V","TZ-")]
        for i,(label,command) in enumerate(actions):
            ttk.Button(blocks,text=label,command=lambda c=command:self.send(c)).grid(row=i//6,column=i%6,padx=2,pady=2,sticky="ew")
        for i in range(6): blocks.columnconfigure(i,weight=1)
        ttk.Label(blocks,text="W/S/A/D：井内前后左右移动；Q/Z、R/F、C/V：三轴±90°；E或Esc：返回演示。").grid(row=2,column=0,columnspan=6,pady=3)
        status = ttk.LabelFrame(self.root, text="板卡反馈", padding=10)
        status.pack(fill="x", padx=12, pady=4)
        ttk.Label(status, textvariable=self.board, wraplength=790).pack(anchor="w")
        ttk.Label(status, textvariable=self.rotation, wraplength=790).pack(anchor="w")
        ttk.Checkbutton(status, text="每2秒查询状态", variable=self.auto).pack(side="left")
        ttk.Button(status, text="立即查询", command=self.query).pack(side="right")
        row = ttk.Frame(self.root)
        row.pack(fill="x", padx=12, pady=8)
        ttk.Label(row, text="指令").pack(side="left")
        self.entry = ttk.Entry(row)
        self.entry.pack(side="left", fill="x", expand=True, padx=6)
        self.entry.bind("<Return>", lambda _e: self.send_entry())
        ttk.Button(row, text="发送（自动加换行）", command=self.send_entry).pack(side="left")
        ttk.Label(self.root, text="画笔/蛇操作保持；方块需配套tetris固件。TF文件和体素文件上传尚未移植。", foreground="#666").pack(anchor="w", padx=12)
        self.logs = scrolledtext.ScrolledText(self.root, height=13, state="disabled", font=("Consolas", 10))
        self.logs.pack(fill="both", expand=True, padx=12, pady=8)
        self.update_buttons()

    def log(self, kind, text):
        self.logs.configure(state="normal")
        self.logs.insert("end", f"{time.strftime('%H:%M:%S')} [{kind}] {text}\n")
        if int(self.logs.index("end-1c").split(".")[0]) > 1500:
            self.logs.delete("1.0", "201.0")
        self.logs.see("end")
        self.logs.configure(state="disabled")

    def update_buttons(self):
        self.scan_btn.configure(state="normal" if not self.busy and not self.ble.connected else "disabled")
        self.connect_btn.configure(state="normal" if not self.busy and not self.ble.connected and self.rows else "disabled")
        self.disconnect_btn.configure(state="normal" if self.ble.connected and not self.busy else "disabled")

    def scan(self):
        self.busy = True
        self.status.set("正在扫描…")
        self.update_buttons()
        self.ble.scan()

    def connect(self):
        index = self.combo.current()
        if index < 0:
            return
        self.busy = True
        self.status.set("正在连接/配对，请留意Windows提示（最长60秒）…")
        self.update_buttons()
        self.ble.connect(self.rows[index][0], self.pair.get())

    def disconnect(self):
        self.busy = True
        self.update_buttons()
        self.ble.disconnect()

    def send(self, command):
        if self.ble.connected:
            if self.mode=="TETRIS":
                command={"JL":"TL","JR":"TR","JU":"TF","JD":"TB","JG":"TG","JP":"TP"}.get(command,command)
            self.ble.send(command)
            # Return keyboard focus after mouse controls so Space hard-drop
            # cannot also invoke a focused ttk button's default binding.
            if isinstance(self.root.focus_get(),ttk.Button): self.root.focus_set()
            requested={"BRUSH":"BRUSH","SNAKE":"SNAKE","TETRIS":"TETRIS","DEMO":"DEMO","JE":"DEMO"}.get(command.upper())
            if requested:
                self.mode=requested
                self.shift=False
                self.query_time=None
                self.root.after(150,self.query) # reconcile optimistic keyboard mapping with actual board mode
        else:
            self.status.set("请先扫描并连接蓝牙")

    def send_entry(self):
        self.send(self.entry.get())

    def query(self):
        if self.ble.connected and self.query_time is None:
            self.query_time = time.monotonic()
            self.last_query = self.query_time
            self.send("STATUS")

    def vertical(self, command):
        if self.ble.connected:
            if self.mode=="TETRIS":
                self.send("TD")
                return
            if self.mode=="SNAKE":
                self.send(command)
                return
            self.send("JB1")
            self.send(command)
            self.send("JB0")

    def change_angle(self, delta):
        if self.ble.connected:
            self.angle = (self.angle + delta) % 100
            self.send(f"JH{self.angle}")

    def key(self, event):
        if isinstance(event.widget, (ttk.Entry, ttk.Combobox, tk.Text)):
            return
        key = event.keysym.lower()
        if not self.ble.connected:
            return
        if self.mode=="TETRIS":
            mapping={"w":"TF","s":"TB","a":"TL","d":"TR","down":"TD",
                     "q":"TX+","z":"TX-","r":"TY+","f":"TY-","c":"TZ+","v":"TZ-",
                     "space":"TH","p":"TP","n":"TG","e":"DEMO","escape":"DEMO",
                     "b":"BRUSH","g":"SNAKE","t":"TETRIS"}
            if key not in mapping: return
            if key not in ("w","s","a","d","down"):
                if key in self.pressed: return
                self.pressed.add(key)
            now=time.monotonic()
            if now-self.last_key.get(key,0)<0.12: return
            self.last_key[key]=now
            self.send(mapping[key]); return
        if self.mode=="SNAKE" or key not in ("w", "s", "a", "d"):
            if key in self.pressed:
                return
            self.pressed.add(key)
        now = time.monotonic()
        interval = 0.12 if key in ("w", "s", "a", "d") else 0.4
        if now - self.last_key.get(key, 0) < interval:
            return
        self.last_key[key] = now
        if self.mode!="SNAKE" and key in ("w", "s", "a", "d"):
            shifted = bool(event.state & 1)
            if shifted != self.shift:
                self.shift = shifted
                self.send("JB1" if shifted else "JB0")
        commands = {"b": "BRUSH", "e": "DEMO", "t":"TETRIS", "g":"SNAKE", "n":"JG", "p": "JP", "k": "JK", "c": "CLEAR",
                    "w": "JU", "s": "JD", "a": "JL", "d": "JR"}
        if self.mode=="SNAKE" and key in ("p","k","c","bracketleft","bracketright"):
            return
        if key in commands:
            self.send(commands[key])
        elif key in ("bracketleft", "bracketright"):
            self.change_angle(-25 if key == "bracketleft" else 25)

    def release_shift(self, _event=None):
        if self.shift:
            self.shift = False
            self.send("JB0")

    def key_release(self, event):
        self.pressed.discard(event.keysym.lower())

    def focus_out(self, _event):
        self.root.after_idle(self.check_focus)

    def check_focus(self):
        if self.root.focus_get() is None:
            self.pressed.clear()
            self.release_shift()

    def open_settings(self):
        try:
            os.startfile("ms-settings:bluetooth")
        except OSError as exc:
            messagebox.showerror("无法打开蓝牙设置", str(exc))

    def poll(self):
        if self.closed:
            return
        for _ in range(150):
            try:
                kind, value = self.ble.events.get_nowait()
            except queue.Empty:
                break
            if kind == "scan":
                self.busy = False
                if value is not None:
                    self.rows = value
                    self.combo["values"] = [f"{'★ ' if r[3] else ''}{r[1]}  {r[0]}  {r[2]}dBm" for r in value]
                    if value:
                        selected = next((i for i, r in enumerate(value) if r[0] == self.saved.get("address")), 0)
                        self.combo.current(selected)
                    self.status.set(f"扫描完成，共{len(value)}台；★为名称/服务匹配的候选")
                else:
                    self.status.set("扫描失败，请检查电脑蓝牙开关并查看日志")
            elif kind in ("connect_done", "disconnect_done"):
                self.busy = False
                if not self.ble.connected:
                    self.status.set("未连接，请查看日志")
            elif kind == "link":
                self.shift = False
                self.pressed.clear()
                self.query_time = None
                self.board.set("板卡状态：等待STATUS回复" if value else "板卡状态：连接已断开")
                self.rotation.set("同步反馈：等待 SYNC 状态" if value else "同步反馈：连接已断开")
                self.status.set("BLE已连接" if value else "BLE已断开，可重新连接")
                if value:
                    index = self.combo.current()
                    if index >= 0:
                        self.saved = {"address": self.rows[index][0]}
                        try:
                            SETTINGS.write_text(json.dumps(self.saved), encoding="utf-8")
                        except OSError as exc:
                            self.log("提示", f"设备地址未保存：{exc}")
                    self.query_time = time.monotonic()
                    self.last_query = self.query_time
            elif kind == "rx":
                self.log("RX", value)
                if value.startswith("SYNC:"):
                    fields = dict(token.split(":", 1) for token in value.split() if ":" in token)
                    state = {"TRACK": "已跟随实测转速", "ADJUST": "正在调整扫描间隔",
                             "ACQUIRE": "已收到首个脉冲，等待下一圈", "LOST": "未锁定，按15转/秒自由显示",
                             "LIMIT": "已测得转速，扫描间隔达到硬件限值"}.get(fields.get("SYNC"), "未知")
                    self.rotation.set(f"同步反馈：{state}；每面 {fields.get('SLICE_US', '?')} μs；"
                                      f"扫描 {fields.get('SCAN_HZ', '?')} 面/秒；"
                                      f"脉冲 {fields.get('ACCEPT', '?')}，拒绝 {fields.get('REJECT', '?')}")
                if "MODE:" in value and "RPM:" in value:
                    self.board.set("板卡在线：" + value)
                    self.query_time = None
                    for token in value.split():
                        if token.startswith("MODE:"):
                            self.mode=token.split(":",1)[1]
                        if token.startswith("A:"):
                            try:
                                self.angle = int(token.split(":")[1]) % 100
                            except ValueError:
                                pass
            else:
                self.log({"error": "错误", "info": "提示", "tx": "TX"}.get(kind, kind), value)
            self.update_buttons()
        now = time.monotonic()
        if self.query_time is not None and now - self.query_time > 4:
            self.query_time = None
            self.board.set("BLE已连接，但未收到板卡状态；检查TX/RX交叉、共地、115200及模块透传模式")
            self.log("提示", "STATUS回复超时；BLE连接成功不代表UART线已接通。")
            self.last_query = now
        if self.auto.get() and self.ble.connected and now - self.last_query > 2:
            self.query()
        self.root.after(50, self.poll)

    def close(self):
        if self.closed:
            return
        self.closed = True
        self.ble.close()
        self.root.withdraw()
        self.wait_closed(time.monotonic() + 4)

    def wait_closed(self, deadline):
        if self.ble.thread.is_alive() and time.monotonic() < deadline:
            self.root.after(50, self.wait_closed, deadline)
        else:
            self.root.destroy()


if __name__ == "__main__":
    App().root.mainloop()
