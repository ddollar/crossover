# Crossover

Zero-downtime Node.js deployments

#### WARNING: Crossover is an experiment in progress and is not recommended for production use.

## Purpose

* Push new versions of an app into production with zero errors and zero dropped requests
* Push new versions using HTTP
* Incrementally roll requests onto the new version, falling back if errors or crashes are encountered

## Installation

	$ npm install -g crossover

## Usage

The example app tarball URLs in these examples actually exist. Feel free to use them for testing.

	$ crossover http://crossover-example.s3.amazonaws.com/app1.tgz
	[master] preparing worker: http://crossover-example.s3.amazonaws.com/app1.tgz
	[master] resolving dependencies
	[master] forked worker 51500
	[master] forked worker 51501	
	[worker:51500] starting app
	[worker:51501] starting app
	[worker:51500] listening on port: 3000
	[worker:51501] listening on port: 3000

## Packaging

Create a tarball that contains your app.

	$ cd ~/Code/myapp
	$ tar czvf ~/Slugs/myapp.tgz .

## Deploying New Code

	$ curl -X POST https://localhost:3000/crossover/release \
	    -d "url=http%3A%2F%2Fcrossover-example.s3.amazonaws.com%2Fapp2.tgz"
	ok

	# meanwhile on the server	
	[master] releasing: http://crossover-example.s3.amazonaws.com/app2.tgz
	[master] preparing worker: http://crossover-example.s3.amazonaws.com/app2.tgz
	[master] resolving dependencies
	[worker:51500] turning off new connections to app
	[worker:51501] turning off new connections to app
	[worker:51500] requests completed, exiting
	[worker:51501] requests completed, exiting
	[master] worker 51500 died
	[master] forked worker 52000
	[master] worker 51501 died
	[master] forked worker 52001
	
## Advanced Usage

	Usage: crossover [options] <slug url>
	
	Options:
	
	  -h, --help               output usage information
	  -V, --version            output the version number
	  -c, --concurrency <num>  number of workers
	  -p, --port <port>        port on which to listen