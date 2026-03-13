require_relative "initializer_hooks"

module CypressRails
  class ManagesTransactions
    def self.instance
      @instance ||= new
    end

    def begin_transaction
      setup_shared_connection_pool

      # Begin transactions for connections already established
      @connection_pools = ActiveRecord::Base.connection_handler.connection_pools(:writing)
      @connection_pools.each do |pool|
        pool.pin_connection!(true)
        pool.lease_connection
      end

      # When connections are established in the future, begin a transaction too
      @connection_subscriber = ActiveSupport::Notifications.subscribe("!connection.active_record") do |_, _, _, _, payload|
        if payload.key?(:spec_name) && (spec_name = payload[:spec_name])

          if spec_name
            pool = ActiveRecord::Base.connection_handler.retrieve_connection_pool(spec_name)
            if pool
              setup_shared_connection_pool

              unless @connection_pools.include?(pool)
                pool.pin_connection!(true)
                pool.lease_connection
                @connection_pools << pool
              end
            end
          end
        end
      end

      @initializer_hooks.run(:after_transaction_start)
    end

    def rollback_transaction
      ActiveRecord::Base.asynchronous_queries_tracker.finalize_session
      ActiveSupport::Notifications.unsubscribe(@connection_subscriber) if @connection_subscriber

      return unless @connection_pools.any?(&:active_connection?)
      @connection_pools.map(&:unpin_connection!)
      @connection_pools.clear

      ActiveRecord::Base.connection_handler.clear_active_connections!
    end

    private

    def initialize
      @initializer_hooks = InitializerHooks.instance
    end

    def gather_connections
      setup_shared_connection_pool

      ActiveRecord::Base.connection_handler.connection_pool_list.map(&:connection)
    end

    # Shares the writing connection pool with connections on
    # other handlers.
    #
    # In an application with a primary and replica the test fixtures
    # need to share a connection pool so that the reading connection
    # can see data in the open transaction on the writing connection.
    def setup_shared_connection_pool
      return unless ActiveRecord::TestFixtures.respond_to?(:setup_shared_connection_pool)
      @legacy_saved_pool_configs ||= Hash.new { |hash, key| hash[key] = {} }
      @saved_pool_configs ||= Hash.new { |hash, key| hash[key] = {} }

      ActiveRecord::TestFixtures.instance_method(:setup_shared_connection_pool).bind(self).call
    end
  end
end
