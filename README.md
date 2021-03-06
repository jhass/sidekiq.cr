# Sidekiq.cr

Sidekiq is a well-regarded background job framework for Ruby.  Now we're
bringing the awesomeness to Crystal, a Ruby-like language.  Why?  To
give you options.  Ruby is friendly and flexible but not terribly fast.
Crystal is statically-typed, compiled and **very fast** but retains a similar syntax to
Ruby.

Rough, initial benchmarks on OSX 10.11.5:

Runtime | RSS | Time | Throughput
--------|-----|------|-------------
MRI 2.3.0 | 50MB | 21.3 | 4,600 jobs/sec
MRI/hiredis | 55MB | 19.2 | 5,200 jobs/sec
Crystal 0.17 | 18MB | 5.9 | 16,900 jobs/sec

If you have jobs which are CPU-intensive or require very high throughput,
Crystal is an excellent alternative to native Ruby extensions.  It
compiles to a single executable so deployment is much easier than Ruby.

# Note

This project is still unstable.  Do not trust it.

## Help wanted

Things that do not exist but I welcome:

* [Data API](https://github.com/mperham/sidekiq/wiki/API)
* [Testing API](https://github.com/mperham/sidekiq/wiki/Testing)
* Web UI
* CI/Build

See also [the issues](https://github.com/mperham/sidekiq.cr/issues) for chores and other ideas to help.

Things that do not exist and probably won't ever:

* Support for daemonization, pidfiles, log rotation.
* Delayed extensions

The Ruby and Crystal versions of Sidekiq **must** remain data compatible in Redis.
Both versions should be able to create and process jobs from each other.
Their APIs **are not** and should not be identical but rather idiomatic to
their respective languages.

## Installation

Add sidekiq.cr to your shards.yml:

```yaml
dependencies:
  sidekiq:
    github: mperham/sidekiq.cr
```

and run `crystal deps`.

## Jobs

A worker class executes jobs.  You create a worker class by including
`Sidekiq::Worker`.  You must define a `perform` method and declare
the types of the arguments using the `perform_types` macro.  **All
arguments to the perform method must be of [JSON::Type](http://crystal-lang.org/api/JSON/Type.html).**

```cr
class SomeWorker
  include Sidekiq::Worker

  perform_types(Int64, String)
  def perform(user_id, email)
  end
end
```

You create a job like so:

```cr
jid = SomeWorker.async.perform(1234_i64, "mike@example.com")
```

Note the difference in syntax to Sidekiq.rb.  It's possible this syntax
will be backported to Ruby.

## Configuration

Because Crystal compiles to a single binary, you need to boot and run
Sidekiq within your code:

```ruby
require "sidekiq/server/cli"
require "your_code"

cli = Sidekiq::CLI.new
server = cli.configure do |config|
  config.server_middleware.add SomeServerMiddleware.new
  config.client_middleware.add SomeClientMiddleware.new

  # Redis is configured through ENV:
  #   REDIS_PROVIDER=REDIS_URL
  #   REDIS_URL=redis://:password@redis.example.com:6379/
end
cli.run(server)
```

This code is still in flux and will likely change, feedback welcome.

## Upgrade?

If you use and like this project, please [let me
know](mailto:mike@contribsys.com).  If demand warrants, I may port
Sidekiq Pro and Enterprise functionality to Crystal for sale.
