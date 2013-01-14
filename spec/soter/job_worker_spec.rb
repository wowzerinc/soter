require 'spec_helper'

describe Soter::JobWorker do

  let(:handler) { FakeHandler } 
  let(:logger)  { FakeLogger.new }
  let(:worker)  { described_class.new }
  let(:job) do
    {
      '_id'           => BSON::ObjectId.new,
      'attempts'      => 0,
      'job'           => {
        'class' => handler.to_s,
        'params' => {}
      },
      'queue_options' => {}
    }
  end

  before :each do
    Soter.queue.stub(:lock_next).and_return(job, nil)
  end

  it "performs expected job"  do
    handler.any_instance.should_receive(:perform)
    
    Soter.queue.should_receive(:complete)

    worker.start
  end

  it "performs correctly in namespaced handlers" do
    job['handler_class'] = Handlers::Fake.to_s
    
    Soter.queue.stub(:complete)
    Handlers::Fake.any_instance.should_receive(:perform)

    worker.start
  end
  
  it "should increment error count if job is unsuccessful"  do
    handler.any_instance.stub(:success?).and_return(false)
    
    Soter.queue.should_receive(:error)

    worker.start
  end

  it "should remove job from queue if wrong handler" do
    Soter.queue.stub(:lock_next).and_return({'handler_class' => 'String'}, nil)

    handler.any_instance.should_receive(:perform).never
    Soter.queue.should_receive(:complete)

    worker.start
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
