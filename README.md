# soter

ruby + mongoid background jobs library

## Install

Install the gem

    gem install soter

Require it

    require 'soter'

## Configure

Initialize configuration values
   
    # REQUIRED
    
    # Host of mongo database
    Soter.config.host = 'localhost'
    
    # Name of mongo database
    Soter.config.db = 'development'

    # OPTIONAL

    # Port of mongo database
    Soter.config.port = '9292'

    # Worker should be forked? (Set to false for testing purposes)
    Soter.config.fork = true
    
    # Logger object to be used
    Soter.config.logger = logger

    # File to log if logger is not defined
    Soter.config.logfile = 'log/dev.log'

    # Max number of workers (defaul is 5)
    Soter.config.workers = 4

## Usage

### Create a job class (Should respond to perform, message, and success?)

    class AJob
      def initialize(options)
        @id     = options['id']
        @status = options['status']
      end

      def perform
        puts 'making something'
      end
      
      def message
        success? ? ':)' : ':('
      end

      def success?
        @status
      end
    end

### Enqueque a job [ Soter.enqueue(handler, options)  ]

* handler: class of the job to be performed
* options: options to be passed to initializer

Example:

    Soter.enqueue(AJob, {id: 'true_job', status: true})

### Dequeue a job [ Soter.dequeue(options) ]

* options: matching options of job or jobs to be removed from queue

Example:

    Soter.dequeue({handler_class: 'AJob', id: 'true_job'})
