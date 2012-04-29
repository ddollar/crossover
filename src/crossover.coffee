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

  constructor: ->
    @app = null
    @listening = false
    @stopping = false
    @workers = []
    @root = temp.mkdirSync("crossover")

  prepare_worker: (dir, cb) =>
    target = @root + "/" + uuid.v1()
    console.log "cloning worker to: #{target}"

    if dir.substring(0,4) == "http"
      rest.get(dir, decoding:"buffer").on "complete", (result) =>
        console.log "result", result
        fs.mkdir target, (err) =>
          fs.writeFile target + "/app.tgz", result, "binary", (err) =>
            this.execute "tar", ["xzvf", "app.tgz"], cwd:target, =>
              this.prepare_npm target, (target) ->
                cb(target)
    else
      wrench.copyDirSyncRecursive(dir, target)
      this.prepare_npm target, (target) ->
        cb(target)

  prepare_npm: (target, cb) =>
    this.execute "npm", ["install"], cwd:target, =>
      this.execute "npm", ["rebuild"], cwd:target, ->
        cb(target)

  spawn_worker: (dir, cb) =>
    console.log "spawning worker: #{dir}"
    worker = cluster.fork()
    worker.send
    worker.dir = dir
    console.log("forked worker #{worker.pid}")
    worker.on "message", (msg) ->
      if msg.cmd is "ready"
        this.send { cmd:"start", dir:dir }
        cb(this) if cb
    worker.on "message", (msg) =>
      if msg.cmd is "release"
        console.log "releasing: #{msg.url}"
        this.prepare_worker msg.url, (dir) =>
          console.log "new slug is: #{dir}"
          @slug = dir
          for worker in @workers
            worker.send { cmd:"stop" }

  listen: (slug, port) =>
    this.error("Must specify a slug.") unless slug
    if cluster.isMaster
      this.prepare_worker slug, (dir) =>
        @slug = dir
        this.master()
    else
      this.slave(port)

  master: =>
    for cpu of os.cpus()
      this.spawn_worker @slug, (worker) =>
        @workers.push(worker)

    # kill a worker
    # setInterval (=> @workers[0].send(cmd:"stop")), 1000

    cluster.on "death", (worker) =>
      console.log("worker #{worker.pid} died")
      @workers.splice(@workers.indexOf(worker), 1)
      this.spawn_worker @slug, (worker) =>
        @workers.push(worker)

  slave: (port) =>
    process.on "message", (msg) =>
      console.log "msg:#{util.inspect(msg)}"
      switch msg.cmd
        when "start"
          @listening = false
          process.env.NODE_PATH = msg.dir
          @app = require(msg.dir + "/index")
          @app.on "close", ->
            console.log "http connections are done: #{process.pid}"
            process.exit(0)
          @app.use("/crossover", this.admin())
          @app.listen port, (=> @listening = true)
        when "stop"
          unless @stopping
            @stopping = true
            console.log "stopping: #{process.pid}"
            if @listening then @app.close() else process.exit(0)
    process.send cmd:"ready"

  admin: () ->
    admin = require("express").createServer(express.bodyParser())
    admin.post "/release", (req, res) ->
      console.log util.inspect(req.body)
      process.send { cmd:"release", url:req.body.url }
      res.send("ok")
    admin

  error: (message) ->
    console.error.apply(console, arguments)
    process.exit(1)

  execute: (command, args, options, cb) ->
    child = spawn(command, args, options)
    child.stdout.on "data", (data) ->
      process.stdout.write "#{data}"
    child.stderr.on "data", (data) ->
      process.stdout.write "#{data}"
    child.on "exit", (code) ->
      console.log("exited with code: #{code}")
      cb(code)

module.exports.create = (slug) ->
  new Crossover(slug)
