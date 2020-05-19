#!/usr/bin/env node

const readlineSync = require('readline-sync');
const noble = require('@abandonware/noble');
const log = require('debug')('am43*');
const debugLog = require('debug')('am43');
const am43 = require('./src/am43');

const yargs = require('yargs');
const args = yargs
    .usage('Usage: $0 MAC1 MAC2 --express-port 3000 --url [mqtt|ws][s]://yourbroker.example.com')
    .example('$0 MAC1 MAC2 --url [broker_url]', 'Connect to devices with specific IDs only, publish to MQTT')
    .options({
        'd': {
            alias: 'debug',
            describe: 'Enable debug logging',
            type: 'boolean'
        },
        'l': {
            alias: 'express-port',
            describe: 'Port for express web server (if unset, express will not startup)',
            type: 'number',
        },
        'url': {
            alias: 'mqtt-url',
            describe: 'MQTT broker URL',
        },
        'topic': {
            alias: 'mqtt-base-topic',
            describe: 'Base topic for MQTT',
            default: 'homeassistant'
        },
        'p': {
            alias: 'mqtt-password',
            describe: 'Password for MQTT (if not specified as an argument, will prompt for password at startup)'
        },
        'u': {
            alias: 'mqtt-username',
            describe: 'Username for MQTT'
        }
    })
    .wrap(yargs.terminalWidth())
    .env('AM43');

const argv = args.argv;

if (argv.debug) {debugLog.enabled = true;}

if (!argv.mqttUrl && !argv.expressPort) {
    log('ERROR: Neither --express-port or --mqtt-url supplied, nothing to do');
    yargs.showHelp();
    process.exit(-1);
}

if (argv.p === true) {
    argv.p = readlineSync.question('MQTT Password: ', {hideEchoBack: true, mask: ''});
}

const idsToConnectTo = argv._.filter(name => !name.startsWith('_')).map(name => name.replace(/:/g, ''));

if(idsToConnectTo.length === 0)
{
    log('ERROR: No MACs defined');
    yargs.showHelp();
    process.exit(-1);
}

argv.expectedDevices = idsToConnectTo.length;

let devices = {};

noble.on('stateChange', (state) => {
    if(state === 'poweredOn') {
        noble.startScanning();
    }
});

if (argv.expectedDevices) {
    log('scanning for %d device(s) %o', argv.expectedDevices, idsToConnectTo);
} else {
    log('scanning for as many devices until timeout');
}

let baseTopic = argv.topic;
if (!baseTopic.endsWith('/')) {
    baseTopic = baseTopic + '/';
}


let mqttUrl = argv.url;
let mqttBinding = require('./src/MQTTConnector');
let mqttUsername = argv.u;
let mqttPassword = argv.p;


let expressPort = argv.l;
if (expressPort) {
    let WebBinding = require('./src/WebConnector');
    new WebBinding(devices, expressPort, debugLog);
}

noble.on('warning', (message) => {debugLog(message)});

noble.on('discover', peripheral => {
    let id = peripheral.address !== undefined ? peripheral.address.replace(/:/g, '') : undefined;

    if (idsToConnectTo.indexOf(id) === -1) {
        debugLog('Found %s but will not connect as it was not specified in the list of devices %o', id, idsToConnectTo);
        return;
    }

    devices[id] = new am43(id, peripheral, noble);
    if (argv.debug) {devices[id].log.enabled = true;}

    log('discovered %s', id);
    if (Object.keys(devices).length === argv.expectedDevices) {
        log('all expected devices connected, stopping scan');
        noble.stopScanning();

        Object.values(devices).forEach((device) => {
            if (mqttUrl) {
                new mqttBinding(device, mqttUrl, baseTopic, mqttUsername, mqttPassword);
            }
            device.am43Init();});
    }


});
