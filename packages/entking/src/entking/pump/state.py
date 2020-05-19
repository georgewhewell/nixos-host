from typing import List

from .motor import FriendlyELEC_NanoHatMotor as MotorController
from .motor import FriendlyELEC_DCMotor as Motor


class MotorState:
    speed: int = 0
    command: str = 'release'


class PumpControllerState:
    addr: int
    freq: int

    def __init__(self, addr=0x60, freq=250):
        self.addr = addr
        self.freq = freq
        self.state = [MotorState() for i in range(4)]
        self.apply()

    def apply(self):
        for motor, state in zip(self.motors, self.state):
            motor.run(state.command)
            motor.setSpeed(state.speed)

    @property
    def controller(self) -> MotorController:
        return MotorController(addr=self.addr, freq=self.freq)

    @property
    def motors(self) -> List[Motor]:
        return [self.controller.getMotor(i+1) for i in range(4)]

    def set_speed(self, num: int, speed: int):
        self.state[num].speed = speed

    def set_command(self, num: int, command: str):
        self.state[num].command = command

    def set_freq(self, freq: int):
        self.freq = freq
