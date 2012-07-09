cluster = require("cluster")
domain  = require("domain")
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

  prepare_worker: (slug, env, cb) =>
    target = @root + "/" + uuid.v1()
    this.log "preparing worker: #{slug}"
    @read_env env, (env) =>
      if slug.substring(0,4) == "http"
        rest.get(slug, decoding:"buffer").on "complete", (result) =>
          fs.mkdir target, (err) =>
            fs.writeFile target + "/app.tgz", result, "binary", (err) =>
              this.execute "tar", ["xzf", "app.tgz"], cwd:target, =>
                this.prepare_npm target, (target) ->
                  cb(target, env)
      else
        wrench.copyDirSyncRecursive(slug, target)
        this.prepare_npm target, (target) ->
          cb(target, env)

  read_env: (env, cb) ->
    if !env
      cb {}
    else if env.substring(0,4) == "http"
      rest.get(env).on "complete", (result) =>
        cb @read_env_data(result)
    else
      fs.readFile env, (err, data) =>
        cb @read_env_data(data.toString())

  read_env_data: (data) ->
    env = {}
    for line in data.split("\n")
      parts = line.split("=")
      env[parts.shift()] = parts.join("=")
    env

  prepare_npm: (target, cb) =>
    this.log "resolving dependencies"
    this.execute "npm", ["install"], cwd:target, =>
      this.execute "npm", ["rebuild"], cwd:target, ->
        cb(target)

  spawn_worker: (dir, cb) =>
    old_env = process.env
    old_cwd = process.cwd()
    process.env = @env || {}
    process.chdir(dir)
    worker = cluster.fork()
    process.chdir(old_cwd)
    process.env = old_env
    this.log("forked worker #{worker.process.pid}")
    worker.on "message", (msg) ->
      if msg.cmd is "ready"
        this.send { cmd:"start", dir:dir }
        cb(this) if cb

  test_worker: (dir, env, cb) =>
    old_env = process.env
    old_cwd = process.cwd()
    process.env = @env || {}
    process.chdir(dir)
    worker = cluster.fork()
    process.chdir(old_cwd)
    process.env = old_env
    this.log("forked worker #{worker.process.pid}")
    worker.on "message", (msg) ->
      if msg.cmd is "ready"
        this.send { cmd:"test", dir:dir }
      else if msg.cmd is "success"
        cb null
      else if msg.cmd is "failure"
        cb msg.err

  listen: (slug, env, port) =>
    this.error("Must specify a slug.") unless slug
    if cluster.isMaster
      this.admin().listen @options["managementPort"], =>
        console.log "[master] listening on management port: #{@options["managementPort"]}"
      this.prepare_worker slug, env, (slug, env) =>
        @slug = slug
        @env = env
        this.master()
    else
      this.slave(port)

  master: =>
    for num in [1..@options.concurrency]
      this.spawn_worker @slug, (worker) =>
        @workers.push(worker)

    cluster.on "exit", (worker) =>
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
          @app = require(msg.dir + "/index")
          @app.on "close", =>
            this.log "requests completed, exiting"
            process.exit(0)
          @app.listen port, =>
            this.log "listening on port: #{port}"
            @listening = true
        when "test"
          this.log "launching test app from slug"
          try
            @app = require(msg.dir + "/index")
            @app.listen 0, =>
              process.send cmd:"success"
          catch err
            process.send cmd:"failure", err:err.toString()

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
      express.basicAuth("admin", (@options['auth'] || "").toString()))
    admin.get "/status", (req, res) ->
      res.contentType "application/json"
      res.send JSON.stringify
        version:
          crossover: module.exports.version
          node:      process.version.substring(1)
    admin.post "/release", (req, res) =>
      dom = domain.create()
      dom.on "error", (err) =>
        @log "failed to launch: #{err}"
        res.writeHead 403
        res.end "error"
      dom.run =>
        slug = req.body.slug
        env  = req.body.env
        @log "releasing: #{slug} #{env}"
        @prepare_worker slug, env, (slug, env) =>
          @test_worker slug, env, (err) =>
            if err
              @log "error in slug, aborting spawn: #{err}"
              res.writeHead 403
              res.end "error"
            else
              @log "test successful"
              @slug = slug
              @env  = env
              worker.send cmd:"stop" for worker in @workers
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
