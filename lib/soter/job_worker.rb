module Soter  
  class JobWorker

    require 'digest/md5'

    def self.start(handler)
      self.new(handler, Soter.logger).start
    end

    def start
      if fork?
        fork do
          perform
        end
      else
        perform
      end
    end

    def initialize(handler, logger)
      @job_handler = handler
      @queue       = Soter.queue
      
      setup_log(logger)
      @queue.cleanup! # remove expired locks
    end

    def setup_log(logger)
      logfile = Soter.config.logfile || 'log/soter.log'
      @log    = logger || File.open("#{logfile}", "a")

      logger.sync = true if logger.respond_to?(:sync=)
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
            job_handler = @job_handler.new(job)
            result = job_handler.perform
            log "#{process_id}: " + job_handler.message

            if job_handler.success?
              @queue.complete(result, process_id)
              log "#{process_id}: Completed job #{job['_id']}"
            else
              @queue.error(result, job_handler.message)
              log "#{process_id}: Failed job #{job['_id']}"
            end

            sleep(1) if fork?
          rescue Exception => e
            @queue.error(job, e.message)
            log "#{process_id}: Failed job #{job['_id']}" +
              " with error #{e.message}"
            log "#{process_id}: Backtrace =>"
            e.backtrace.each { |line| log "#{process_id}: #{line}"}
          end
      end #while
      log "#{process_id}: Harakiri"
      logger.close
    end #start

    def fork?
      Soter.config.fork
    end


    def logger
      @log
    end

    def log(message)
      @log << message + "\n"
    end


  end
end
