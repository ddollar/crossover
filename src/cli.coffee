crossover = require("./crossover")
os        = require("os")
program   = require("commander")
util      = require("util")

program
  .version(crossover.version)
  .usage('[options] <slug url>')
  .option('-a, --auth <password>', 'admin password')
  .option('-c, --concurrency <num>', 'number of workers', os.cpus().length)
  .option('-e, --env <url>', 'environment file')
  .option('-p, --port <port>', 'port on which to listen', 3000)

module.exports.execute = (args) ->
  program.parse(args)
  crossover.create(program).listen(program.args[0], program.env, program.port)
