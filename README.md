# Sidekiq::PrioritizedQueues

Adds numeric based priorities to your jobs. This is done by monkey patching the following classes:

- `Sidekiq::Client`
- `Sidekiq::Stats`
- `Sidekiq::Queue`
- `Sidekiq::Job`

This gem also adds a new priority based Fetcher, and a middleware that sets priority on the jobs.

**WARNING: This changes the type of the `queue:<name>` keys. There's no migration helper in place, so the easiest way is to start off with a clean setup.**

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq-prioritized_queues'
```

## Usage

Simply having the gem in your Gemfile is enough to get started with prioritized jobs. As a default, priority will be the timestamp at which the job is enqueued, as to simulate the default FIFO order.

### Priority

There are two ways of specifying priority:

#### Static

This is useful whenever different workers share the same queue. An example would be:

```ruby
class SatisfySameDayOrderWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'orders', priority: 0

  def perform(order)
    # Do stuff here
  end
end

class SatisfyOrderWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'orders', priority: 1

  def perform(order)
    # Do stuff here
  end
end
```

#### Dynamic

For workers on the same queue, the `priority` option can take a `Proc` which will be given the arguments the job was queued with. As an example:

```ruby
class HeavyWorker
  include Sidekiq::Worker
  sidekiq_options priority: -> (account_id) {
    Account.find(account_id).vip? ? 0 : 10
  }

  def perform(account_id)
    # Do some work.
  end
end
```

The example above would make sure that VIP accounts get processed first.

### Queue Resolution

The `queue` option also supports dynamic resolution through a `Proc`. This allows you to route jobs to different queues based on their arguments:

```ruby
class ProcessOrderWorker
  include Sidekiq::Worker
  sidekiq_options queue: -> (order_id) {
    order = Order.find(order_id)
    order.premium? ? 'premium_orders' : 'standard_orders'
  }

  def perform(order_id)
    # Process the order
  end
end
```

The queue name will be automatically converted to a string, and if the `Proc` returns `nil` or an empty string, the queue will default to `'default'`.

### Ignored Queues

By default, all queues use priority-based (sorted set) operations. However, you can configure specific queues to use traditional FIFO (list-based) operations by marking them as "ignored queues". This is useful when you want certain queues to maintain strict FIFO ordering without priority sorting.

Ignored queues are configured in `config/sidekiq_prioritized_queues.yml`:

```yaml
ignored_queues:
  - webhooks
  - notifications
  - cleanup
```

With this configuration:
- Jobs in the `webhooks`, `notifications`, and `cleanup` queues will be processed in strict FIFO order
- Jobs in all other queues will be processed based on their priority values
- You can still use priority-based and dynamic queue routing for workers, but if they push to an ignored queue, the job will be enqueued using FIFO

This is particularly useful for queues where order of execution is critical and you don't want priority-based reordering to affect the processing sequence.

## Contributing

1. Fork it ( https://github.com/publitas/sidekiq-prioritized_queues/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
