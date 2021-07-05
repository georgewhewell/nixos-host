import paho.mqtt.client as mqtt

MQTT_PREFIX = "homeassistant/switch/pump{num}"


def config(num):
    return {
        'name': f"Water Pump {num}",
        'unique_id': f"pump-{num}",
        'device': {
            'manufacturer': 'george',
        },
        'state_topic': MQTT_PREFIX.format(num=num) + '/state',
        'command_topic': MQTT_PREFIX.format(num=num) + '/cmd',
    }



class MQTTClient:

    def __init__(self, mqtt_hostname, mqtt_username, mqtt_password):
        self.client = mqtt.Client()
        self.client.on_connect = on_connect
        self.client.on_message = on_message

    def setup_motor(self, num):
        print(f"Sending autoconf for {motor}")
        self.client.subscribe(MQTT_PREFIX.format(num=num) + '/cmd')
        self.client.publish(
            MQTT_PREFIX.format(motor.motornum) + '/config',
            config(motor.motornum),
        )

    def on_connect(self, client, userdata, flags, rc):
        print("Connected with result code "+str(rc))
        for motor in self.motor_controller.motors:
            self.setup_motor(motor.num)

    def on_message(self, client, userdata, msg):
        print(msg.topic)
        print(msg.payload)
