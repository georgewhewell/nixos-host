from flask import Flask, send_file
from tempfile import NamedTemporaryFile

print("Starting app")

try:
    print('Importing pumps..')
    from .pump.state import PumpControllerState
    pump_controller = PumpControllerState()
except (ImportError, FileNotFoundError) as exc:
    print(f'Failed to import pump: {exc}')
    pump_controller = None

try:
    print('Importing bt sensors..')
    from .sensors.miflora import pollers
except (ImportError, FileNotFoundError) as exc:
    print(f'Failed to import sensors: {exc}')
    pollers = None

try:
    print('Importing tank sensor..')
    from .sensors.tank_level import get_distance
except (ImportError, FileNotFoundError) as exc:
    print(f'Failed to import sensors: {exc}')
    get_distance = None

try:
    print('Importing camera..')
    from .camera.capture import capture_image
except ImportError as exc:
    print(f'Failed to import camera: {exc}')

app = Flask(__name__)
@app.route('/')
def test():
    return {'hello': 'world'}


@app.route('/motors')
def motor_list():
    return {}

@app.route('/frequency/<frequency>', methods=["POST"])
def frequency(frequency):
    pump_controller.set_freq(int(frequency))
    pump_controller.apply()
    return 'OK'

@app.route('/motors/<motor>/forward', methods=['POST'])
def forward(motor):
    pump_controller.set_command(int(motor), 'forward')
    pump_controller.apply()
    return 'OK'

@app.route('/motors/<motor>/release', methods=['POST'])
def release(motor):
    pump_controller.set_command(int(motor), 'release')
    pump_controller.apply()
    return 'OK'

@app.route('/motors/<motor>/speed/<speed>', methods=['POST'])
def set_speed(motor, speed):
    pump_controller.set_speed(int(motor), int(speed))
    pump_controller.apply()
    return 'OK'

@app.route('/tank', methods=['GET'])
def get_tank_level():
    return {
        'distance': get_distance()
    }

@app.route('/capture')
def get_camera():
    with NamedTemporaryFile(suffix='.png') as capture_file:
        capture_image(capture_file.name)
        return send_file(capture_file.name)

def serve():
    app.run(host='0.0.0.0', port=8000)
