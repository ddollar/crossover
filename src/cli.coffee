crossover = require("./crossover")
program   = require("commander")

program
  .version(crossover.version)
  .usage('[options]')
  .option('-p, --port <port>', 'port on which to listen', 3000)
  .option('-s, --slug <slug>', 'initial slug')

module.exports.execute = (args) ->
  program.parse(args)
  server = crossover.create()
  server.listen(program.port)
