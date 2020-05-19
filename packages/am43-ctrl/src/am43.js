const EventEmitter = require('events');

const serviceUUID = '0000fe5000001000800000805f9b34fb';
const am43CharUUID = '0000fe5100001000800000805f9b34fb';

const NOBLE_SERVICE_UID = "fe50";
const NOBLE_BAT_CHAR_UID = "fe51";

const AM43HANDLE = 0x000e;

const HEX_KEY_OPEN_BLINDS = "00ff00009a0d010096";
const HEX_KEY_CLOSE_BLINDS = "00ff00009a0d0164f2";
const HEX_KEY_STOP_BLINDS = "00ff00009a0a01cc5d";

const HEX_KEY_POSITION_BLINDS_PREFIX = "00ff0000";
const HEY_KEY_POSITION_BLIND_FIXED_CRC_CONTENT = "9a0d01";

const HEX_KEY_BATTERY_REQUEST = "00ff00009aa2010138";
const HEY_KEY_LIGHT_REQUEST = "00ff00009aaa010130";
const HEY_KEY_POSITION_REQUEST = "00ff00009aa701013d";

const batteryNotificationIdentifier = "a2";
const positionNotificationIdentifier = "a7";
const lightNotificationIdentifier = "aa";

const fullMovingTime = 137000;

class am43 extends EventEmitter {
    static busyDevice = null;

    constructor(id, peripheral, noble) {
        super();
        this.log = require('debug')(`am43:${id}`);
        this.id = id;
        this.peripheral = peripheral;
        this.noble = noble;
        this.connecttime = null;
        this.lastaction = null;
        this.state = null;
        this.currentRetry = 0;
        this.maxRetries = 30;
        this.success = false;
        this.batterysuccess = false;
        this.lightsuccess = false;
        this.positionsuccess = false;
        this.batterypercentage = null;
        this.lightpercentage = null;
        this.positionpercentage = null;
    }

    writeLog(pLogLine) {
        this.log(pLogLine);
    }

    readData() {
        if (am43.busyDevice != null) {
            this.writeLog('Connection busy for other device, delaying data read...');
            setTimeout(() => {
                this.readData()
            }, 1000);
            return;
        }

        this.performReadData();
    }

    performReadData() {
        this.batterysuccess = false;
        this.positionsuccess = false;
        this.lightsuccess = false;
        am43.busyDevice = this;

        this.peripheral.connect();
        this.peripheral.once('connect', handleDeviceConnected);
        this.peripheral.once('disconnect', disconnectMe);
        const self = this;

        function handleDeviceConnected() {
            self.connecttime = new Date();
            self.writeLog('AM43 connected for data reading');
            var characteristicUUIDs = [NOBLE_BAT_CHAR_UID];
            var serviceUID = [NOBLE_SERVICE_UID];
            self.peripheral.removeAllListeners('servicesDiscover');
            self.peripheral.discoverSomeServicesAndCharacteristics(serviceUID, characteristicUUIDs, discoveryResult);
        }

        function disconnectMe() {
            self.writeLog('disconnected for data reading');

            if (self.batterysuccess === false || self.positionsuccess === false || self.lightsuccess === false) {
                if (self.currentRetry < self.maxRetries) {
                    self.writeLog("Reading data unsuccessful, retrying in 1 second...");
                    self.currentRetry = self.currentRetry + 1;
                    setTimeout(() => {
                        self.performReadData()
                    }, 1000);
                } else {
                    self.writeLog("Reading data unsuccessful, giving up...");
                    am43.busyDevice = null;
                    self.currentRetry = 0;
                }
            } else {
                self.writeLog("Reading data was successful");
                am43.busyDevice = null;
                self.currentRetry = 0;
                self.emit('stateChanged', self.getState());
            }
        }

        function discoveryResult(error, services, characteristics) {
            if (error) {
                self.writeLog("ERROR retrieving characteristic");
                self.peripheral.disconnect();
            } else {
                self.writeLog('discovered data char');
                let characteristic = characteristics[0];
                characteristic.on('data', function (data, isNotification) {
                    self.writeLog('received characteristic update');
                    //read data to buffer
                    let bfr = Buffer.from(data, "hex");
                    //convert to hex string
                    let strBfr = bfr.toString("hex", 0, bfr.length);
                    self.writeLog('Notification data: ' + strBfr);
                    let notificationIdentifier = strBfr.substr(2, 2);
                    self.writeLog('Notification identifier: ' + notificationIdentifier);
                    if (batteryNotificationIdentifier === notificationIdentifier) {
                        //battery is hexadecimal on position 14, 2 bytes
                        let batteryHex = strBfr.substr(14, 2);
                        //convert hex number to integer
                        let batteryPercentage = parseInt(batteryHex, 16);
                        self.writeLog('Bat %: ' + batteryPercentage);
                        self.batterypercentage = batteryPercentage;
                        self.batterysuccess = true;

                        //write cmd to enable light notification
                        characteristic.write(Buffer.from(HEY_KEY_LIGHT_REQUEST, "hex"), true);
                    } else if (lightNotificationIdentifier === notificationIdentifier) {
                        //light is byte 4 (ex. 9a aa 02 00 00 32)
                        let lightHex = strBfr.substr(8, 2);
                        //convert to integer
                        let lightPercentage = parseInt(lightHex, 16);
                        self.writeLog('Light %: ' + lightPercentage);
                        self.lightpercentage = lightPercentage;
                        self.lightsuccess = true;

                        //write cmd to get position
                        characteristic.write(Buffer.from(HEY_KEY_POSITION_REQUEST, "hex"), true);
                    } else if (positionNotificationIdentifier === notificationIdentifier) {
                        //position is byte 6: 9a a7 07 0f 32 4e 00 00 00 30 79
                        let positionHex = strBfr.substr(10, 2);
                        //convert to integer
                        let positionPercentage = parseInt(positionHex, 16);
                        self.writeLog('Position %: ' + positionPercentage);
                        self.positionpercentage = positionPercentage;
                        self.positionsuccess = true;
                        self.reevaluateState();
                    }

                    if (self.batterysuccess && self.lightsuccess && self.positionsuccess) {
                        self.writeLog("Reading data completed");
                        characteristic.unsubscribe();
                        setTimeout(() => {
                            self.peripheral.disconnect();
                        }, 1000);
                    }
                });
                //subscribe to notifications on the char
                characteristic.subscribe();
                //write cmd to enable battery notification
                characteristic.write(Buffer.from(HEX_KEY_BATTERY_REQUEST, "hex"), true);
            }
        }
    }

    writeKey(handle, key) {
        if (am43.busyDevice != null) {
            this.writeLog('Connection busy for other device, waiting...');
            setTimeout(() => {
                this.writeKey(handle, key)
            }, 1000);
            return;
        }

        this.performWriteKey(handle, key);
    }

    performWriteKey(handle, key) {
        this.success = false;
        am43.busyDevice = this;
        this.peripheral.connect();
        this.peripheral.once('connect', handleDeviceConnected);
        this.peripheral.once('disconnect', disconnectMe);
        const self = this;

        function handleDeviceConnected() {
            self.connecttime = new Date();
            self.writeLog('AM43 connected');
            self.peripheral.writeHandle(handle, Buffer.from(key, "hex"), true, handleWriteDone);
        }

        function disconnectMe() {
            self.writeLog('disconnected');
            if (self.success === false) {
                if (self.currentRetry < self.maxRetries) {
                    self.writeLog("Writing unsuccessful, retrying in 1 second...");
                    self.currentRetry = self.currentRetry + 1;
                    setTimeout(() => {
                        self.performWriteKey(handle, key)
                    }, 1000);
                } else {
                    self.writeLog("Writing unsuccessful, giving up...");
                    am43.busyDevice = null;
                    self.currentRetry = 0;
                }
            } else {
                self.writeLog("Writing was successful");
                am43.busyDevice = null;
                self.currentRetry = 0;
                self.emit('stateChanged', self.getState());
                self.scheduleForcedDataRead();
            }
        }

        function handleWriteDone(error) {
            if (error) {
                self.writeLog('ERROR' + error);
            } else {
                self.writeLog('key written');
                self.success = true;
            }

            setTimeout(() => {
                self.peripheral.disconnect();
            }, 1000);
        }
    }

    am43Init() {
        const self = this;

        setTimeout(() => {
            self.readData()
        }, 5000);

        const interval = this.randomIntMinutes(10, 20);
        this.writeLog("interval: " + interval);
        setInterval(() => {
            self.readData();
        }, interval);
    }

    scheduleForcedDataRead() {
        const self = this;
        //we read data after 15 seconds (eg. to capture pretty fast the open state)
        setTimeout(() => {
            self.readData()
        }, 15000);

        //we read data after fullMovingTime + 5 seconds buffer (eg. to capture the closed state/end position when movement is complete)
        setTimeout(() => {
            self.readData()
        }, fullMovingTime + 5000);

        //else we still have our 'slower' backup task which will provide updated data at later time
    }

    randomIntMinutes(min, max) {
        return 1000 * 60 * (Math.floor(Math.random() * (max - min + 1) + min));
    }

    reevaluateState() {
        if (this.positionpercentage === 100) {
            this.state = 'CLOSED';
        } else {
            this.state = 'OPEN';
        }
    }

    am43Open() {
        this.writeKey(AM43HANDLE, HEX_KEY_OPEN_BLINDS);
        this.lastaction = 'OPEN';
        this.state = 'OPEN';
    }

    am43Close() {
        this.writeKey(AM43HANDLE, HEX_KEY_CLOSE_BLINDS);
        this.lastaction = 'CLOSE';
        this.state = 'CLOSED';
    }

    am43Stop() {
        this.writeKey(AM43HANDLE, HEX_KEY_STOP_BLINDS);
        this.lastaction = 'STOP';
        this.state = 'OPEN';
    }

    am43GotoPosition(position)
    {
        var positionHex = position.toString(16);
        if(positionHex.length === 1)
        {
            positionHex = "0" + positionHex;
        }
        var buffer = Buffer.from(HEY_KEY_POSITION_BLIND_FIXED_CRC_CONTENT + positionHex, "hex");
        var crc = buffer[0];
        for (var i=1; i<buffer.length; i++) {
            crc = crc ^ buffer[i];
        }

        this.writeKey(AM43HANDLE, HEX_KEY_POSITION_BLINDS_PREFIX + HEY_KEY_POSITION_BLIND_FIXED_CRC_CONTENT + positionHex + crc.toString(16));
        this.lastaction = 'SET_POSITION';
        if(position === 100)
        {
            this.state = 'CLOSED';
        }
        else
        {
            this.STATE = 'OPEN';
        }
    }

    getState() {
        return {
            id: this.id,
            lastconnect: this.connecttime,
            lastaction: this.lastaction,
            state: this.state,
            battery: this.batterypercentage,
            light: this.lightpercentage,
            position: this.positionpercentage
        };
    }
}

module.exports = am43;
