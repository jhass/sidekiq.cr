module Sidekiq
  module Middleware
    # #
    # Automatically retry jobs that fail in Sidekiq.
    # Sidekiq's retry support assumes a typical development lifecycle:
    #
    #   0. Push some code changes with a bug in it.
    #   1. Bug causes job processing to fail, Sidekiq's middleware captures
    #      the job and pushes it onto a retry queue.
    #   2. Sidekiq retries jobs in the retry queue multiple times with
    #      an exponential delay, the job continues to fail.
    #   3. After a few days, a developer deploys a fix. The job is
    #      reprocessed successfully.
    #   4. Once retries are exhausted, Sidekiq will give up and move the
    #      job to the Dead Job Queue (aka morgue) where it must be dealt with
    #      manually in the Web UI.
    #   5. After 6 months on the DJQ, Sidekiq will discard the job.
    #
    # A job looks like:
    #
    #     { 'class' => 'HardWorker', 'args' => [1, 2, 'foo'], 'retry' => true }
    #
    # The 'retry' option also accepts a number (in place of 'true'):
    #
    #     { 'class' => 'HardWorker', 'args' => [1, 2, 'foo'], 'retry' => 5 }
    #
    # The job will be retried this number of times before giving up. (If simply
    # 'true', Sidekiq retries 25 times)
    #
    # We'll add a bit more data to the job to support retries:
    #
    #  * 'queue' - the queue to use
    #  * 'retry_count' - number of times we've retried so far.
    #  * 'error_message' - the message from the exception
    #  * 'error_class' - the exception class
    #  * 'failed_at' - the first time it failed
    #  * 'retried_at' - the last time it was retried
    #  * 'backtrace' - the number of lines of error backtrace to store
    #
    # We don't store the backtrace by default as that can add a lot of overhead
    # to the job and everyone is using an error service, right?
    #
    # The default number of retry attempts is 25 which works out to about 3 weeks
    # of retries. You can pass a value for the max number of retry attempts when
    # adding the middleware using the options hash:
    #
    #   Sidekiq.configure_server do |config|
    #     config.server_middleware do |chain|
    #       chain.add Sidekiq::Middleware::Server::RetryJobs, :max_retries => 7
    #     end
    #   end
    #
    # or limit the number of retries for a particular worker with:
    #
    #    class MyWorker
    #      include Sidekiq::Worker
    #      sidekiq_options :retry => 10
    #    end
    #
    class RetryJobs < Entry
      DEFAULT_MAX_RETRY_ATTEMPTS = 25

      def initialize
        @max_retries = DEFAULT_MAX_RETRY_ATTEMPTS
      end

      def call(job, ctx)
        yield
      rescue e : Exception
        raise e unless retries(job.retry) > 0
        attempt_retry(job, ctx, e)
      end

      def retries(retry : JSON::Type)
        if retry.is_a?(Bool)
          retry.as(Bool) ? DEFAULT_MAX_RETRY_ATTEMPTS : 0
        elsif retry.is_a?(Int64)
          retry.to_i
        else
          0
        end
      end

      def traces(trace : JSON::Type)
        if trace.is_a?(Bool)
          trace.as(Bool) ? 1000 : 0
        elsif trace.is_a?(Int64)
          trace.to_i
        else
          0
        end
      end

      def attempt_retry(job, ctx, exception)
        max_retry_attempts = retries(job.retry)

        job.error_message = exception.message
        job.error_class = exception.class.name
        count = if job.retry_count.nil?
                  job.failed_at = Time.now
                  job.retry_count = 0_i64
                else
                  job.retried_at = Time.now
                  c = job.retry_count.not_nil!
                  c += 1
                  job.retry_count = c
                end

        tcount = traces(job.backtrace)
        job.error_backtrace = exception.backtrace[0...tcount] if tcount > 0

        if count < max_retry_attempts
          delay = delay_for(job, count, exception)
          ctx.logger.debug { "Failure! Retry #{count} in #{delay} seconds" }
          retry_at = Time.now + delay.seconds
          payload = job.to_json
          ctx.pool.redis do |conn|
            conn.zadd("retry", "%.6f" % retry_at.epoch_f, payload)
          end
        else
          # Goodbye dear message, you (re)tried your best I'm sure.
          retries_exhausted(job, ctx, exception)
        end

        raise exception
      end

      def retries_exhausted(job, ctx, exception)
        ctx.logger.debug { "Retries exhausted for job" }

        send_to_morgue(job, ctx) unless job.dead == false
      end

      def send_to_morgue(job, ctx)
        ctx.logger.info { "Adding dead #{job.klass} job #{job.jid}" }
        payload = job.to_json
        now = Time.now
        ctx.pool.redis do |conn|
          conn.multi do
            conn.zadd("dead", "%.6f" % now.epoch_f, payload)
            conn.zremrangebyscore("dead", "-inf", now - 6.months)
            conn.zremrangebyrank("dead", 0, -10_000)
          end
        end
      end

      def delay_for(job, count, exception)
        seconds_to_delay(count)
      end

      # delayed_job uses the same basic formula
      def seconds_to_delay(count)
        (count ** 4) + 15 + (rand(30)*(count + 1))
      end
    end
  end
end
