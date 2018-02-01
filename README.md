[![CircleCI](https://circleci.com/gh/westernmilling/adp_client.svg?style=svg&circle-token=3d5bf2ba7d231f1eae04c432b7775cf5499df917)](https://circleci.com/gh/westernmilling/adp_client)
[![Maintainability](https://api.codeclimate.com/v1/badges/bb49c51e2a887464a6e9/maintainability)](https://codeclimate.com/github/westernmilling/adp_client/maintainability)
[![Test Coverage](https://api.codeclimate.com/v1/badges/bb49c51e2a887464a6e9/test_coverage)](https://codeclimate.com/github/westernmilling/adp_client/test_coverage)

# AdpClient

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'adp_client'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install adp_client

## Usage

```ruby
  client = AdpClient.new(
    client_id: ENV['ADP_CLIENT_ID'],
    client_secret: ENV['ADP_CLIENT_SECRET'],
    base_ur: ENV['ADP_API_HOST'],
    pem: File.read(ENV['ADP_SSL_CERT_PATH'])
  )

  event_data = client.get('events/time/v1/data-collection-entries.process/3d2ae46e-8f94-4fa8-ade1-fe554d93ed71')
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/westernmilling/adp_client. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the AdpClient project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/westernmilling/adp_client/blob/master/CODE_OF_CONDUCT.md).
