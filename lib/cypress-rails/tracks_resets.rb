require_relative "resets_state"

module CypressRails
  class TracksResets
    def self.instance
      @instance ||= new
    end

    def reset_needed!
      @reset_needed = true
    end

    # One reset at a time. Without the lock, anything else that passes through
    # the Rails executor while a reset is running (the next request, Action
    # Cable work from a page still open) sees the flag still set and starts a
    # second reset alongside the first. A caller that waited finds the flag
    # cleared and does nothing; if the reset raised, the flag is still set and
    # the caller runs it again.
    def reset_state_if_needed(transactional_server)
      @lock.synchronize do
        if @reset_needed
          ResetsState.new.call(transactional_server: transactional_server)
          @reset_needed = false
        end
      end
    end

    private

    def initialize
      @reset_needed = false
      @lock = Mutex.new
    end
  end
end
