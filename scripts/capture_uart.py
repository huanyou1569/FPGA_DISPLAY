"""Read the board USB UART without sending data or asserting DTR/RTS."""
import argparse
from pathlib import Path
import time
import serial

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--port',default='COM16')
parser.add_argument('--seconds',type=float,default=60)
parser.add_argument('--output',required=True,type=Path)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
output=args.output.resolve()
if not output.is_relative_to(root):
    raise SystemExit('Capture output must remain inside this project')
deadline=time.monotonic()+args.seconds
with output.open('wb') as log:
    while time.monotonic()<deadline:
        uart=serial.Serial(port=None,baudrate=115200,bytesize=8,parity='N',stopbits=1,
                           timeout=0.2,xonxoff=False,rtscts=False,dsrdtr=False)
        uart.port=args.port;uart.dtr=False;uart.rts=False
        try:
            uart.open()
            print('LISTENING '+args.port,flush=True)
            while time.monotonic()<deadline:
                data=uart.read(4096)
                if data:
                    log.write(data);log.flush()
                    print(data.decode('ascii',errors='backslashreplace'),end='',flush=True)
        except serial.SerialException as exc:
            print('UART disconnected/unavailable: '+str(exc),flush=True)
            time.sleep(0.5)
        finally:
            if uart.is_open:uart.close()
print('CAPTURE_COMPLETE',flush=True)
