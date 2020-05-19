module Soter
  class JobWorker

    require 'digest/md5'
    require 'securerandom'

    def initialize
      @queue        = Soter.queue
      @log          = Soter.config.logger || logfile
      @callbacks    = Soter.callbacks
      @queue_misses = 0

      @log.sync = true if @log.respond_to?(:sync=)
    end

    def start
      schrodingers_fork do
        Soter.job_worker(true)
        touch_worker_file
        Soter.reset_database_connections if fork?

        @callbacks[:worker_start].each  { |callback| callback.call(fork?) }
        perform
        @callbacks[:worker_finish].each { |callback| callback.call(fork?) }

        delete_worker_file
        Soter.job_worker(false)
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
      log "Spawning"

      while true
        unless job = @queue.lock_next(worker_id)
          @queue_misses += 1

          log "Queue miss ##{@queue_misses}"

          break if queue_miss_sleep_seconds <= 0

          if @queue_misses >= queue_misses_limit
            break
          else
            sleep(queue_miss_sleep_seconds)
            next
          end
        end

        GC.start
        @callbacks[:job_start].each { |callback| callback.call(job) }
        touch_worker_file
        start_time = Time.now
        log "Starting work on job #{job['_id']}"
        log "Job info =>"

        job.each {
          |key, value| log  "{#{key} : #{value}}" }

        begin
          handler_class = Soter.recursive_const_get(job['job']['class'])
          job_handler   = handler_class.new(job['job']['params'], 'id' => job['_id'])

          job_handler.perform

          log job_handler.message

          if job_handler.success?
            @queue.complete(job, worker_id)
            log "Completed job #{job['_id']}"
          else
            offset           = Soter.retry_offset(job['attempts']+1)
            job['active_at'] = Time.now.utc + offset

            @queue.error(job, job_handler.message)
            log "Failed job #{job['_id']}"
          end
        rescue Exception => e
          @queue.complete(job, worker_id)
          log "Failed job #{job['_id']}" +
            " with error #{e.message}"
          log "Backtrace =>"
          e.backtrace.each { |line| log line }
          report_error(e)
        ensure
          @callbacks[:job_finish].each { |callback| callback.call(job) }

          end_time = Time.now
          log "Time taken: #{end_time - start_time}"
        end

        break if Soter.worker_slots_full?
      end #while
      log "Harakiri"
      @log.close
    end #start

    def report_error(exception)
      @callbacks[:job_error].each { |callback| callback.call(exception) }
    end

    def worker_id
      @worker_id ||=
        Digest::MD5.
        hexdigest("#{Socket.gethostname}-#{Process.pid}-#{Thread.current}-#{SecureRandom.uuid.gsub("-", "")}")
    end

    def fork?
      !!Soter.config.fork
    end

    def worker_relative_file_path
      Soter.worker_relative_directory + '/' + worker_id
    end

    def touch_worker_file
      FileUtils.mkdir_p(File.dirname(worker_relative_file_path))
      FileUtils.touch(worker_relative_file_path)
    end

    def delete_worker_file
      File.delete(worker_relative_file_path) if
        File.exist?(worker_relative_file_path)
    end

    def logfile
      filename = Soter.config.logfile || 'log/soter.log'
      FileUtils.mkdir_p(File.dirname(filename))

      File.open(filename, "a")
    end

    def log(message)
      @log << "[#{worker_id}][#{Time.now.iso8601}]" + message + "\n"
    end

    def queue_misses_limit
      Soter.config.worker_misses_limit
    end

    def queue_miss_sleep_seconds
      Soter.config.worker_miss_sleep
    end

  end
end
