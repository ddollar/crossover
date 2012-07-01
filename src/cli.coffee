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
  .option('-m, --management-port <num>', 'management port', 3000)
  .option('-p, --port <port>', 'port on which to listen', 5000)

module.exports.execute = (args) ->
  program.parse(args)
  crossover.create(program).listen(program.args[0], program.env, program.port)
