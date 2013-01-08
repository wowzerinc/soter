require 'spec_helper'

describe Soter do

  let(:handler) { FakeHandler }
  let(:options) { {option: 'an_option'} }
  let(:logger)  { FakeLogger.new }
  let(:job_options) { options.merge({'handler_class' => 'FakeHandler'}) }

  it 'configures correctly' do
    Soter.config.host = 'host'
    Soter.config.port = 'port'
    Soter.config.db   = 'test'

    Soter.config.queue_settings.should == {
      host:       'host',
      port:       'port',
      database:   'test',
      collection: 'mongo_queue',
      timeout:    300,
      attempts:   3
    }
  end

  it 'enqueues a job' do
    Soter.queue.should_receive(:insert).with(job_options)
    Soter::JobWorker.any_instance.should_receive(:start)

    Soter.enqueue(handler, options)
  end

  it 'dequeues a job' do
    Soter.queue.should_receive(:remove).with(options)
    
    Soter.dequeue(options)
  end

  it 'sets logger correctly' do
    Soter.logger = logger

    Soter.logger.should == logger
  end

  it "dispatches at most the specified number of workers" do
    Soter.queue.should_receive(:insert).with(job_options)
    Soter.queue.should_receive(:cleanup!).once
    
    Soter.enqueue(handler, options)
  end

  context "Forking" do

    before :each do
      Soter.config.fork = true
    end

    it "dispatches workers sucessfully" do
      pending("Concurrent tests are hard, what should we test?")
    end

  end
end
