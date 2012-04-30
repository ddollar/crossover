var express = require('express');

var app = express.createServer(express.logger());

app.get('/', function(req, res) {
  console.log('got request: app1');
  res.send('ok');
});

module.exports = app;
