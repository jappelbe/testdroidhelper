# Testdroidhelper

Helper for queuing devices for testdroid remote control session. If you do not know what testdroid is, this is of no value for you.

## Installation

Add this line to your application's Gemfile:

    gem 'testdroidhelper'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install testdroidhelper

## Expected usage (simplified):

td_provider = TestdroidHelper::RemoteCOnnectionProvider.new
device_ids = td_provider.get_devices_array.map {|dev| dev.first}
td_provider.setup_test # target_concurrency should be smaller than thread count
1.upto(YOUR_THREAD_COUNT) do |i|
  device_id = device_ids.pop
  remote = td_provider.get_device(device_id)
  # Do remote stuff here
  remote.get_screenshot
end

## Contributing

1. Fork it ( http://github.com/jappelbe/testdroidhelper/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

Unit tests can be run:
rake spec
