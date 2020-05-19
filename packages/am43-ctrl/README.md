# AM43 Blinds Drive Controller Util
Util for controlling a am43 Cover, either over MQTT or via a HTTP API. When used over MQTT it works together with home-assistant and performs auto disovery configuration of the cover component.
(Eg. https://nl.aliexpress.com/item/4000106179323.html)
This util should work with all blind drives which make use of the Blind Engine App. (A-OK, Zemismart,...)

# Hardware Installation
Install the blinds and configure top and bottom positions through the BlindsEngine App.
Retrieve the MacAddress of the device (for example by using nRF Connect app for android)

# Installation
Run `npm install https://github.com/binsentsu/am43-ctrl`

For making the application persistent across device reboots a possibility is to use pm2:
https://www.npmjs.com/package/pm2

# Usage
`sudo am43ctrl` by itself will print usage information

You need to manually specify a list of MAC addresses to connect to, e.g.: `sudo am43ctrl f5:11:7b:ee:f3:43`


You must then specify options to use either MQTT, HTTP or both

## To use with HTTP
Specify a port for the API to listen on with `-l`:
`sudo am43ctrl MACx MACy -l 3000`

## To use with MQTT
Specify a broker URL with `--url` option:
`sudo am43ctrl --url mqtt://yourbroker` (mqtt/mqtts/ws/wss accepted)

Username and password for MQTT may be specified with `-u` and `-p` option

If no password argument is supplied, you can enter it interactively

Base topic defaults to `homeassistant`, but may be configured with the `-topic` option


# MQTT
To issue commands:

OPEN: `<baseTopic>/cover/<deviceID>/set` - message: 'OPEN'

CLOSE: `<baseTopic>/cover/<deviceID>/set` - message: 'CLOSE'

STOP: `<baseTopic>/cover/<deviceID>/set` - message: 'STOP'

SET_POSITION: 
100 is closed
0 is open
`<baseTopic>/cover/<deviceID>/setposition` - message: '21'

In addition, for use with [Home Assistant MQTT Discovery](https://www.home-assistant.io/docs/mqtt/discovery/):

Three entities will be pubished to homeassistant discovery topic:

```
Cover: 

{
    "name": "MAC",
    "availability_topic": "homeassistant/cover/MACx/connection",
    "payload_available": "Online",
    "payload_not_available": "Offline",
    "command_topic": "homeassistant/cover/MACx/set",
    "position_topic": "homeassistant/cover/MACx/state",
    "set_position_topic" : "homeassistant/cover/MACx/setposition",
    "position_open": 0,
    "position_closed": 100,
    "payload_open": "OPEN",
    "payload_close": "CLOSE",
    "payload_stop": "STOP",
    "unique_id": "am43_MACx_cover",
    "value_template": '{{value_json[\'position\']}}',
    "device": {
        "identifiers": "am43_MACx",
        "name": "MACx",
        "manufacturer": "Generic AM43"
    }
}

Battery Sensor:

{
    "name": "MAC Battery",
    "availability_topic": "homeassistant/cover/MACx/connection",
    "state_topic": "homeassistant/cover/MACx/state
    "payload_available": "Online",
    "payload_not_available": "Offline",
    "device_class" : "battery",
    "unit_of_measurement": "%",
    "unique_id": "am43_MACx_battery_sensor",
    "value_template": '{{value_json[\'battery\']}}',
    "device": {
        "identifiers": "am43_MACx",
        "name": "MACx",
        "manufacturer": "Generic AM43"
    }
}

Light Sensor:

{
    "name": "MAC Battery",
    "availability_topic": "homeassistant/cover/MACx/connection",
    "state_topic": "homeassistant/cover/MACx/state
    "payload_available": "Online",
    "payload_not_available": "Offline",
    "unit_of_measurement": "%",
    "unique_id": "am43_MACx_light_sensor",
    "value_template": '{{value_json[\'light\']}}',
    "device": {
        "identifiers": "am43_MACx",
        "name": "MACx",
        "manufacturer": "Generic AM43"
    }
}

```

## Parameters

`<deviceID>` has format of the device's MAC address in lowercase, with the colon's stripped out and cannot be changed


# HTTP Endpoints

`GET /`: list devices.
Response type: `[String : Device]` - ID as String key, Device as value
```
{
   "c03dc8105277":{
      "id":"c03dc8105277",
      "lastconnect":"2019-11-23T17:39:48.949Z",
      "lastaction":"OPEN",
      "state":"OPEN",
      "battery":42,
      "light":0,
      "position":0
   }
}
```

`GET /<deviceID>`: Get individual device data (or 404 if no device by that ID).

Response type: `Device` example:
```
{
   "id":"c03dc8105277",
   "lastconnect":"2019-11-23T17:39:48.949Z",
   "lastaction":"OPEN",
   "state":"OPEN",
   "battery":42,
   "light":0,
   "position":0
}
```

`POST /<deviceID>/open`: Send OPEN command to am43. Response type: `200 - OK` or `404 - Not Found`

`POST /<deviceID>/close`: Send CLOSE command to am43. Response type: `200 - OK` or `404 - Not Found`

`POST /<deviceID>/stop`: Send STOP command to am43. Response type: `200 - OK` or `404 - Not Found`
