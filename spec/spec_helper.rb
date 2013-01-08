require_relative '../lib/soter.rb'

class FakeLogger
  def <<(s); (@log ||= '') << s; end
  def log; @log; end
  def close; end
  def reset; @log = ''; end
end

class FakeHandler
  def perform
  end

  def message
    'message'
  end
  
  def success?
    true
  end
end
