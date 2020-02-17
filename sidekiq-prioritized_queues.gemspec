# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sidekiq/prioritized_queues/version'

Gem::Specification.new do |spec|
  spec.name          = "sidekiq-prioritized_queues"
  spec.version       = Sidekiq::PrioritizedQueues::VERSION
  spec.authors       = ["Andre Medeiros"]
  spec.email         = ["me@andremedeiros.info"]
  spec.summary       = %q{Numeric priorities for queues on Sidekiq}
  spec.description   = %q{Changes your queues from FIFO to numeric priority based ones.}
  spec.homepage      = "https://github.com/publitas/sidekiq-prioritized_queues"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "sidekiq", "~> 6.0", ">= 6.0.4"

  spec.add_development_dependency "bundler", "~> 1.17"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "sinatra"
end
