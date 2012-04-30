var express = require('express');
var uuid = require('node-uuid');

var app = express.createServer(express.logger());

app.get('/', function(req, res) {
  console.log('got request: app2');
  res.send('ok: ' + uuid.v4());
});

module.exports = app;
