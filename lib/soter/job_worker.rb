module Soter
  class JobWorker

    require 'digest/md5'

    def initialize
      @queue     = Soter.queue
      @log       = Soter.config.logger || logfile
      @callbacks = Soter.callbacks

      @log.sync = true if @log.respond_to?(:sync=)
    end

    def start
      schrodingers_fork do
        @callbacks[:start].each  { |callback| callback.call(fork?) }
        perform
        @callbacks[:finish].each { |callback| callback.call(fork?) }
      end
    end

    private

    def schrodingers_fork
      if fork?
        process_id = fork { yield; exit }
        Process.detach(process_id)
      else
        yield
      end
    end

    def perform
      process_id = Digest::MD5.
        hexdigest("#{Socket.gethostname}-#{Process.pid}-#{Thread.current}")

      log "#{process_id}: Spawning"

      while(job = @queue.lock_next(process_id))
        log "#{process_id}: Starting work on job #{job['_id']}"
        log "#{process_id}: Job info =>"

        job.each {
          |key, value| log  "#{process_id}: {#{key} : #{value}}" }

        begin
          handler_class = Soter.recursive_const_get(job['job']['class'])
          job_handler   = handler_class.new(job['job']['params'])

          job_handler.perform

          log "#{process_id}: " + job_handler.message

          if job_handler.success?
            @queue.complete(job, process_id)
            log "#{process_id}: Completed job #{job['_id']}"
          else
            offset           = Soter.retry_offset(job['attempts']+1)
            job['active_at'] = Time.now.utc + offset
            @queue.error(job, job_handler.message)

            log "#{process_id}: Failed job #{job['_id']}"
          end

          sleep(1) if fork?
        rescue Exception => e
          @queue.complete(job, process_id)
          log "#{process_id}: Failed job #{job['_id']}" +
            " with error #{e.message}"
          log "#{process_id}: Backtrace =>"
          e.backtrace.each { |line| log "#{process_id}: #{line}"}
          report_error(e)
        end
      end #while
      log "#{process_id}: Harakiri"
      @log.close
    end #start

    def report_error(exception)
      @callbacks[:error].each { |callback| callback.call(exception) }
    end

    def fork?
      !!Soter.config.fork
    end

    def logfile
      filename = Soter.config.logfile || 'log/soter.log'
      FileUtils.mkdir_p(File.dirname(filename))

      File.open(filename, "a")
    end

    def log(message)
      @log << message + "\n"
    end

  end
end
