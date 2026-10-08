require "test_helper"

class TracksResetsTest < Minitest::Test
  # Stands in for ResetsState: records each reset and takes long enough for a
  # second caller to arrive while it is still running.
  class SlowReset
    attr_reader :calls

    def initialize
      @calls = Queue.new
    end

    def call(transactional_server:)
      @calls << transactional_server
      sleep 0.2
    end
  end

  class FailingReset
    def call(transactional_server:)
      raise "reset failed"
    end
  end

  def test_that_a_caller_arriving_during_a_reset_does_not_run_a_second_one
    reset = SlowReset.new
    tracker = CypressRails::TracksResets.new
    tracker.reset_needed!

    resetting_with(reset) do
      Array.new(2) { Thread.new { tracker.reset_state_if_needed(false) } }.each(&:join)
    end

    assert_equal 1, reset.calls.size
  end

  def test_that_a_reset_that_raises_is_still_needed
    reset = SlowReset.new
    tracker = CypressRails::TracksResets.new
    tracker.reset_needed!

    resetting_with(FailingReset.new) do
      assert_raises(RuntimeError) { tracker.reset_state_if_needed(false) }
    end
    resetting_with(reset) { tracker.reset_state_if_needed(false) }

    assert_equal 1, reset.calls.size
  end

  private

  # ResetsState needs a booted Rails app, so swap in a stand-in for the block.
  def resetting_with(reset)
    CypressRails::ResetsState.define_singleton_method(:new) { reset }
    yield
  ensure
    CypressRails::ResetsState.singleton_class.send(:remove_method, :new)
  end
end
