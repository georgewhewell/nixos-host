const express = require('express');

class WebConnector {
    constructor(devices, port, log) {
        this.devices = devices;
        this.express = express();
        this.setupExpressRoutes();
        this.log = log;
        this.log('listening on port %d', port);
        this.express.listen(port);
    }

    setupExpressRoutes() {
        this.express.get('/', (req, res) => {
            var output = {};
            Object.entries(this.devices).forEach(([id, device]) => output[id] = device.getState());
            res.json(output);
        });

        this.express.get('/:am43Id', (req, res) => {
            let device = this.requireDevice(req, res);
            if (!device) {return;}

            res.json(device.getState());
        });

        this.express.post('/:am43Id/open', (req, res) => {
            let device = this.requireDevice(req, res);
            if (!device) {
                return;
            }

            device.log('requesting AM43 open');
            device.am43Open();
            res.sendStatus(200);
        });

        this.express.post('/:am43Id/close', (req, res) => {
            let device = this.requireDevice(req, res);
            if (!device) {
                return;
            }

            device.log('requesting AM43 close');
            device.am43Close();
            res.sendStatus(200);
        });

        this.express.post('/:am43Id/stop', (req, res) => {
            let device = this.requireDevice(req, res);
            if (!device) {
                return;
            }

            device.log('requesting AM43 stop');
            device.am43Stop();
            res.sendStatus(200);
        });
    }

    requireDevice(req, res) {
        var device = this.devices[req.params.am43Id];
        if (!device) {
            res.sendStatus(404);
            return;
        }

        return device;
    }
}

module.exports = WebConnector;
