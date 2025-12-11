require 'yaml'

module Sidekiq
  module PrioritizedQueues
    class Config
      attr_reader :config

      def initialize(sidekiq_config)
        @config = load_gem_config(sidekiq_config[:require] || '.')
      end

      def ignored_queues
        @config.fetch(:ignored_queues, [])
      end

      private

      def load_gem_config(app_path)
        config_file_path = File.join(app_path, 'config', 'sidekiq_prioritized_queues.yml')
        gem_config = {}

        if File.exist?(config_file_path)
          begin
            gem_config = YAML.safe_load_file(config_file_path) || {}
            if gem_config.respond_to?(:deep_symbolize_keys!)
              gem_config.deep_symbolize_keys!
            else
              gem_config = symbolize_keys_deep(gem_config)
            end
          rescue Psych::SyntaxError, Psych::Exception => e
            warn "Sidekiq::PrioritizedQueues: Failed to load config file at #{config_file_path}: #{e.class}: #{e.message}"
            gem_config = {}
          end
        end

        gem_config.is_a?(Hash) ? gem_config.compact : {}
      end

      def symbolize_keys_deep(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), result|
            key = k.respond_to?(:to_sym) ? k.to_sym : k
            result[key] = symbolize_keys_deep(v)
          end
        when Array
          obj.map { |v| symbolize_keys_deep(v) }
        else
          obj
        end
      end
    end
  end
end
