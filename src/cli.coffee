crossover = require("./crossover")
program   = require("commander")
util      = require("util")

program
  .version(crossover.version)
  .usage('[options] <slug>')
  .option('-p, --port <port>', 'port on which to listen', 3000)

module.exports.execute = (args) ->
  program.parse(args)
  crossover.create().listen(program.args[0], program.port)
