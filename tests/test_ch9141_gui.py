"""Tk smoke checks using queue events only: never scans/connects real BLE hardware."""
import time
import unittest
from types import SimpleNamespace

from ch9141_upper import App


class WindowTests(unittest.TestCase):
    def setUp(self):
        self.app = App()
        self.app.root.withdraw()
        self.app.root.update()

    def tearDown(self):
        self.app.close()
        deadline = time.monotonic() + 5
        while self.app.ble.thread.is_alive() and time.monotonic() < deadline:
            self.app.root.update()
            time.sleep(.02)
        self.assertFalse(self.app.ble.thread.is_alive(), "BLE worker leaked")
        try:
            self.app.root.destroy()
        except Exception:
            pass

    def test_status_angle_and_disconnect(self):
        self.app.ble.events.put(('rx', 'RPM:0 DLY:0 MODE:BRUSH BX:1 BY:2 BZ:3 A:25 DR:1'))
        self.app.poll()
        self.assertEqual(self.app.angle, 25)
        self.assertIn('MODE:BRUSH', self.app.board.get())
        self.app.shift = True
        self.app.ble.events.put(('link', False))
        self.app.poll()
        self.assertFalse(self.app.shift)
        self.assertIn('断开', self.app.board.get())

    def test_typing_in_entry_does_not_send_brush_commands(self):
        self.app.ble.connected = True
        sent = []
        self.app.ble.send = sent.append
        self.app.key(SimpleNamespace(widget=self.app.entry, keysym='p', state=0))
        self.assertEqual(sent, [])
        self.app.ble.connected = False

    def test_rotation_sync_feedback(self):
        for state, label in [('TRACK','已跟随'),('LIMIT','硬件限值'),('ACQUIRE','下一圈'),
                             ('ADJUST','正在调整'),('LOST','自由显示')]:
            self.app.ble.events.put(('rx',f'SYNC:{state} SLICE_US:555 SCAN_HZ:1800 ACCEPT:20 REJECT:2'))
            self.app.poll()
            self.assertIn(label,self.app.rotation.get())
            self.assertIn('555',self.app.rotation.get())
        self.app.ble.events.put(('link',False))
        self.app.poll()
        self.assertIn('已断开',self.app.rotation.get())

    def test_snake_mode_feedback_and_key_repeat(self):
        self.app.ble.events.put(('rx', 'RPM:900 MODE:SNAKE A:51 SCORE:3 HIGH:7 STATE:PLAY LEN:8'))
        self.app.poll()
        self.assertEqual(self.app.mode, 'SNAKE')
        self.app.ble.connected = True
        sent = []
        self.app.ble.send = sent.append
        key=SimpleNamespace(widget=self.app.root,keysym='w',state=1)
        self.app.key(key)
        self.app.last_key.clear()
        self.app.key(key)
        self.assertEqual(sent,['JU']) # snake gets one turn per physical press, no brush modifier
        self.app.key_release(key)
        self.app.last_key.clear()
        self.app.key(SimpleNamespace(widget=self.app.root,keysym='n',state=0))
        self.assertEqual(sent[-1],'JG')
        self.app.ble.connected = False

    def test_tetris_mapping_preserves_snake_keys(self):
        self.app.ble.events.put(('rx','RPM:900 MODE:TETRIS A:51 SCORE:10 STATE:PLAY PLANES:1'))
        self.app.poll(); self.assertEqual(self.app.mode,'TETRIS')
        self.app.ble.connected=True; sent=[];self.app.ble.send=sent.append
        for key in ['w','q','z','r','f','c','v','space','p','n']:
            self.app.key(SimpleNamespace(widget=self.app.root,keysym=key,state=0))
        self.assertEqual(sent,['TF','TX+','TX-','TY+','TY-','TZ+','TZ-','TH','TP','TG'])
        self.app.send('JL'); self.assertEqual(sent[-1],'TL')
        self.app.mode='SNAKE';self.app.send('JG');self.assertEqual(sent[-1],'JG')
        self.app.ble.connected=False


if __name__ == '__main__':
    unittest.main()
