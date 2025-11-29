module Sidekiq
  module PrioritizedQueues
    class Middleware
      def call(worker_class, msg, queue, redis_pool)
        klass = case worker_class
        when String then constantize(worker_class)
        else worker_class
        end

        priority = klass.get_sidekiq_options['priority']

        msg['priority'] = case priority
        when Proc   then priority.call(*msg['args'])
        when String then priority.to_i
        when Integer then priority
        else Time.now.to_f
        end

        klass_queue = klass.get_sidekiq_options['queue']
        msg['queue'] = (klass_queue.is_a?(Proc) ? klass_queue.call(*msg['args']) : klass_queue).to_s
        yield
      end

      def constantize(str)
        return Object.const_get(str) unless str.include?("::")

        names = str.split("::")
        names.shift if names.empty? || names.first.empty?

        names.inject(Object) do |constant, name|
          # the false flag limits search for name to under the constant namespace
          #   which mimics Rails' behaviour
          constant.const_get(name, false)
        end
      end
    end
  end
end
