require 'spec_helper'

describe Soter::JobWorker do

  let(:handler) { FakeHandler } 
  let(:logger)  { FakeLogger.new }
  let(:worker)  { described_class.new(handler, logger) }
  let(:job)     { {'_id' => 1} }

  it "reschedules unsuccessful requests" do
    pending('define retry logic')
  end

  before :each do
    Soter.queue.stub(:lock_next).and_return(job,nil)
  end

  it "performs expected job"  do
    handler.any_instance.should_receive(:perform)
    Soter.queue.should_receive(:complete)

    worker.start
  end

  it "should queue an error if job is unsuccessful"  do
    handler.any_instance.stub(:success?).and_return(false)
    Soter.queue.should_receive(:error)

    worker.start
  end

  it "should queue an error with a bad job" do
    wrong_worker = described_class.new('wrong_handler', logger)
    Soter.queue.should_receive(:error)

    wrong_worker.start
  end

  it "rescues itself from a locked queue" do
    pending('what does this means?')
    old_timeout = QUEUE_SETTINGS[:timeout]
    QUEUE_SETTINGS[:timeout] = 0
    JobDispatcher.instance_variable_set("@queue", nil)

    QUEUE_SETTINGS[:workers].times do 
      JobDispatcher.queue.insert(:to => "test@test.com")
      JobDispatcher.queue.lock_next("test")
    end

    JobDispatcher.mail(:to => "test@test.com")
    JobDispatcher.workers.should be_blank
    QUEUE_SETTINGS[:timeout] = old_timeout
  end

end
