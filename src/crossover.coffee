cluster = require("cluster")
express = require("express")
fs      = require("fs")
os      = require("os")
rest    = require("restler")
spawn   = require("child_process").spawn
temp    = require("temp")
util    = require("util")
uuid    = require("node-uuid")
wrench  = require("wrench")

module.exports.version = require("../package.json").version

class Crossover

  constructor: (@options) ->
    @app = null
    @listening = false
    @stopping = false
    @workers = []
    @root = temp.mkdirSync("crossover")

  prepare_worker: (dir, cb) =>
    target = @root + "/" + uuid.v1()
    this.log "preparing worker: #{dir}"

    if dir.substring(0,4) == "http"
      rest.get(dir, decoding:"buffer").on "complete", (result) =>
        fs.mkdir target, (err) =>
          fs.writeFile target + "/app.tgz", result, "binary", (err) =>
            this.execute "tar", ["xzf", "app.tgz"], cwd:target, =>
              this.prepare_npm target, (target) ->
                cb(target)
    else
      wrench.copyDirSyncRecursive(dir, target)
      this.prepare_npm target, (target) ->
        cb(target)

  prepare_npm: (target, cb) =>
    this.log "resolving dependencies"
    this.execute "npm", ["install"], cwd:target, =>
      this.execute "npm", ["rebuild"], cwd:target, ->
        cb(target)

  spawn_worker: (dir, cb) =>
    worker = cluster.fork()
    this.log("forked worker #{worker.pid}")
    worker.on "message", (msg) ->
      if msg.cmd is "ready"
        this.send { cmd:"start", dir:dir }
        cb(this) if cb
    worker.on "message", (msg) =>
      if msg.cmd is "release"
        this.log "releasing: #{msg.url}"
        @url = msg.url
        this.prepare_worker msg.url, (dir) =>
          @slug = dir
          for worker in @workers
            worker.send cmd:"stop"

  listen: (slug, port) =>
    this.error("Must specify a slug.") unless slug
    if cluster.isMaster
      @url = slug
      this.prepare_worker slug, (dir) =>
        @slug = dir
        this.master()
    else
      this.slave(port)

  master: =>
    for num in [1..@options.concurrency]
      this.spawn_worker @slug, (worker) =>
        @workers.push(worker)

    # kill a worker
    # setInterval (=> @workers[0].send(cmd:"stop")), 1000

    cluster.on "death", (worker) =>
      this.log("worker #{worker.pid} died")
      @workers.splice(@workers.indexOf(worker), 1)
      this.spawn_worker @slug, (worker) =>
        @workers.push(worker)

  slave: (port) =>
    process.on "message", (msg) =>
      switch msg.cmd
        when "start"
          this.log "starting app"
          @listening = false
          process.env.NODE_PATH = msg.dir
          @app = require(msg.dir + "/index")
          @app.on "close", =>
            this.log "requests completed, exiting"
            process.exit(0)
          @app.use("/crossover", this.admin())
          @app.listen port, =>
            this.log "listening on port: #{port}"
            @listening = true
        when "stop"
          unless @stopping
            @stopping = true
            if @listening
              this.log "turning off new connections to app"
              @app.close()
              setTimeout (=>
                this.log "giving up on remaining connections"
                process.exit(0)
              ), 30000
            else
              this.log "app not listening yet, exiting"
              process.exit(0)
    process.send cmd:"ready"

  admin: () ->
    admin = require("express").createServer(
      express.bodyParser(),
      express.basicAuth("", @options['auth'].toString()))
    admin.post "/release", (req, res) =>
      process.send { cmd:"release", url:req.body.url }
      res.send("ok")
    admin

  format_log: (args) ->
    pid = if cluster.isMaster then "master" else "worker:#{process.pid}"
    formatted = ["[#{pid}]"]
    for arg in args
      formatted.push(arg)
    formatted

  log: ->
    console.log.apply(console, this.format_log(arguments))

  error: ->
    args = ["[#{process.pid}]"]
    for arg in arguments
      args.push(arg)
    console.error.apply(console, args)
    process.exit(1)

  execute: (command, args, options, cb) =>
    child = spawn(command, args, options)
    child.stdout.on "data", (data) ->
      for part in data.toString().replace(/\n$/, '').split("\n")
        console.log "[compiler] #{part}" if process.env.DEBUG
    child.stderr.on "data", (data) ->
      for part in data.toString().replace(/\n$/, '').split("\n")
        console.log "[compiler] #{part}" if process.env.DEBUG
    child.on "exit", (code) =>
      cb(code)

module.exports.create = (slug) ->
  new Crossover(slug)
