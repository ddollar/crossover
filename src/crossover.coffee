cluster = require("cluster")
express = require("express")
os      = require("os")
util    = require("util")

module.exports.version = require("../package.json").version

class Crossover

  constructor: ->
    @app = null
    @listening = false
    @stopping = false
    @workers = []

  spawn_worker: (dir, cb) ->
    console.log "spawning worker: #{dir}"
    worker = cluster.fork()
    worker.dir = dir
    console.log("forked worker #{worker.pid}")
    @workers.push(worker)
    worker.on "message", (msg) ->
      switch msg.cmd
        when "ready"
          this.send { cmd:"start", dir:dir }
          cb(worker) if cb
        when "release"
          console.log "releasing: #{msg.dir}"
          for worker in @workers
            console.log "worker: #{worker}"
            worker.send { cmd:"stop" }

  listen: (port) ->
    if cluster.isMaster
      this.master();
    else
      this.slave(port);

  master: ->
    for cpu of os.cpus()
      this.spawn_worker("/Users/david/Code/vulcan/server")

    # kill a worker
    # setInterval (-> @workers[0].send("stop")), 500

    cluster.on "death", (worker) ->
      console.log("worker #{worker.pid} died")
      @workers.splice(@workers.indexOf(worker), 1)
      this.spawn_worker(worker.dir)

  slave: (port) =>
    process.on "message", (msg) =>
      console.log "msg:#{util.inspect(msg)}"
      switch msg.cmd
        when "start"
          listening = false
          dir = msg.dir
          process.env.NODE_PATH = dir
          app = require(dir + "/index")
          app.on "close", ->
            console.log "http connections are done: #{process.pid}"
            process.exit(0)
          app.use("/bogon", this.admin())
          app.listen port, ->
            listening = true
        when "stop"
          unless stopping
            stopping = true
            console.log "stopping: #{process.pid}"
            app.close() if listening

    process.send { cmd:"ready" }

  admin: () ->
    admin = require("express").createServer(express.bodyParser())
    admin.post "/release", (req, res) ->
      process.send { cmd:"release", dir:req.body.url }
      res.send("ok")
    admin

module.exports.create = ->
  new Crossover()
