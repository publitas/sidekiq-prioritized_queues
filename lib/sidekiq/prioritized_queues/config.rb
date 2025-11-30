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
          gem_config = YAML.safe_load_file(config_file_path)
          if gem_config.respond_to?(:deep_symbolize_keys!)
            gem_config.deep_symbolize_keys!
          else
            symbolize_keys_deep!(gem_config)
          end
        end

        gem_config.is_a?(Hash) ? gem_config.compact : {}
      end

      def symbolize_keys_deep!(hash)
        hash.keys.each do |k|
          symkey = k.respond_to?(:to_sym) ? k.to_sym : k
          hash[symkey] = hash.delete k
          symbolize_keys_deep! hash[symkey] if hash[symkey].is_a? Hash
        end
        hash
      end
    end
  end
end
