#!/usr/bin/python

from .pwm import PWM
import time

class FriendlyELEC_DCMotor:

    FORWARD = 'forward'
    BACKWARD = 'backward'
    RELEASE = 'release'

    def __init__(self, controller, num):
        self.MC = controller
        self.motornum = num
        pwm = in1 = in2 = 0

        if (num == 0):
            pwm = 0     #8
            in2 = 1     #9
            in1 = 2     #10
        elif (num == 1):
            pwm = 5     #13
            in2 = 4     #12
            in1 = 3     #11
        elif (num == 2):
            pwm = 15    #2
            in2 = 14    #3
            in1 = 13    #4
        elif (num == 3):
            pwm = 10    #7
            in2 = 11    #6
            in1 = 12    #5
        else:
            raise NameError('NanoHat Motor must be between 1 and 4 inclusive')
        self.PWMpin = pwm
        self.IN1pin = in1
        self.IN2pin = in2

    def run(self, command):
        if not self.MC:
            return
        if (command == FriendlyELEC_DCMotor.FORWARD):
            self.MC.setPin(self.IN2pin, 0)
            self.MC.setPin(self.IN1pin, 1)
        if (command == FriendlyELEC_DCMotor.BACKWARD):
            self.MC.setPin(self.IN1pin, 0)
            self.MC.setPin(self.IN2pin, 1)
        if (command == FriendlyELEC_DCMotor.RELEASE):
            self.MC.setPin(self.IN1pin, 0)
            self.MC.setPin(self.IN2pin, 0)

    def setSpeed(self, speed):
        if (speed < 0):
            speed = 0
        if (speed > 255):
            speed = 255
        self.MC._pwm.setPWM(self.PWMpin, 0, speed*16)



class FriendlyELEC_NanoHatMotor:
    FORWARD = 1
    BACKWARD = 2
    BRAKE = 3
    RELEASE = 4

    SINGLE = 1
    DOUBLE = 2
    INTERLEAVE = 3
    MICROSTEP = 4

    def __init__(self, addr = 0x60, freq = 1600):
        self._i2caddr = addr            # default addr on HAT
        self._frequency = freq        # default @1600Hz PWM freq
        self.motors = [FriendlyELEC_DCMotor(self, m) for m in range(4)]
        self._pwm =  PWM(addr, debug=False)
        self._pwm.setPWMFreq(self._frequency)

    def setPin(self, pin, value):
        if (pin < 0) or (pin > 15):
            raise NameError('PWM pin must be between 0 and 15 inclusive')
        if (value != 0) and (value != 1):
            raise NameError('Pin value must be 0 or 1!')
        if (value == 0):
            self._pwm.setPWM(pin, 0, 4096)
        if (value == 1):
            self._pwm.setPWM(pin, 4096, 0)

    def getStepper(self, steps, num):
        if (num < 1) or (num > 2):
            raise NameError('NanoHat Stepper must be between 1 and 2 inclusive')
        return self.steppers[num-1]

    def getMotor(self, num):
        if (num < 1) or (num > 4):
            raise NameError('NanoHat Motor must be between 1 and 4 inclusive')
        return self.motors[num-1]
