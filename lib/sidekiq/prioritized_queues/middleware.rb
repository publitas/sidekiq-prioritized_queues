module Sidekiq
  module PrioritizedQueues
    class Middleware
      def call(worker_class, msg, queue, redis_pool)
        klass = case worker_class
        when String then worker_class.constantize
        else worker_class
        end

        priority = klass.get_sidekiq_options['priority']

        msg['priority'] = case priority
        when Proc   then priority.call(*msg['args'])
        when String then priority.to_i
        when Integer then priority
        else Time.now.to_f
        end

        yield
      end
    end
  end
end
