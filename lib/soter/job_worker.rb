module Soter  
  class JobWorker

    require 'digest/md5'

    def start(retry_job=true)
      if fork?
        fork do
          perform(retry_job)
        end
      else
        perform(retry_job)
      end
    end

    def initialize
      @queue       = Soter.queue
      @log         = Soter.config.logger || File.open("#{logfile}", "a")

      @log.sync = true if @log.respond_to?(:sync=)
      @queue.cleanup! # remove expired locks
    end

    def perform(retry_job)
      process_id = Digest::MD5.
        hexdigest("#{Socket.gethostname}-#{Process.pid}-#{Thread.current}")

      log "#{process_id}: Spawning"

      while(job = @queue.lock_next(process_id))
        log "#{process_id}: Starting work on job #{job['_id']}"
        log "#{process_id}: Job info =>"

        job.each {
          |key, value| log  "#{process_id}: {#{key} : #{value}}" }
          
          begin
            job_handler = eval(job['handler_class']).new(job['options'])
            
            job_handler.perform

            log "#{process_id}: " + job_handler.message

            if job_handler.success? || !retry_job
              @queue.complete(job, process_id)
              log "#{process_id}: Completed job #{job['_id']}"
            else
              @queue.error(job, job_handler.message)
              job['active_at'] = Time.now.utc + retry_offset(job['attempts']) 
              
              log "#{process_id}: Failed job #{job['_id']}"
            end

            sleep(1) if fork?
          rescue Exception => e
            @queue.complete(job, e.message)
            log "#{process_id}: Failed job #{job['_id']}" +
              " with error #{e.message}"
            log "#{process_id}: Backtrace =>"
            e.backtrace.each { |line| log "#{process_id}: #{line}"}
          end
      end #while
      log "#{process_id}: Harakiri"
      @log.close
    end #start

    def fork?
      Soter.config.fork
    end

    def logfile
      Soter.config.logfile || 'log/soter.log'
    end

    def log(message)
      @log << message + "\n"
    end

    def retry_offset(attempts)
      (attempts ** 3) * (15 * 60)
    end

  end
end
