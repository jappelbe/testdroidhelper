require 'logger'
require 'bundler'
Bundler.setup(:default, :rake)
require 'testdroidhelper'

raise ArgumentError.new("(Only got #{ARGV.count} params, 4 required) Usage: #{$0} <username> <password> <project_name> <test_app_path>") unless ARGV.count == 4
USERNAME, PASSWORD, PROJECT_NAME, TEST_APP_PATH = ARGV
CONCURRENCY = 50 # target_concurrency should be smaller than thread count
THREAD_COUNT = 105

INCL_DEV_FILTER = /.*/i
EXCL_DEV_FILTER = /(iphone|ipad|apple|ipod)/i

stdout_log = Logger.new($stdout)

alt_logger = Logger.new("altlog.log")

stdout_log.info('Setting up RemoteConnectionProvider')
td_provider = TestdroidHelper::RemoteConnectionProvider.new(USERNAME, PASSWORD, alt_logger)

stdout_log.info('Selecting devices')
device_ids_array = td_provider.get_devices_array(INCL_DEV_FILTER, EXCL_DEV_FILTER)
device_ids_array.map! {|dev| dev.first}


raise "No devices left after filtering!" if device_ids_array.empty?

stdout_log.info("Setting up test (#{device_ids_array.count} devices)")
td_provider.setup_test(PROJECT_NAME, TEST_APP_PATH, device_ids_array, CONCURRENCY)

results = Queue.new
td_provider.execute_on_all_devices(THREAD_COUNT) do |remote, device_id, thread_index|
  begin
    device_name = td_provider.get_device_name(device_id)
    stdout_log.info "Thread#{thread_index}, rolled device with id = '#{device_id}', name = '#{device_name}'"

    # Get properties
    devprops = remote.device_properties
    height = devprops['display.height'].to_i
    width = devprops['display.width'].to_i
    fail "Couldn't get proper resolution (got '#{width.inspect}x#{height.inspect}') " unless height.is_a?(Fixnum) and height.is_a?(Fixnum)

    # Touch screen
    middle = [width/2, height/2]
    remote.touch(*(middle.sort.reverse))

    # Press back button
    back_key = 4
    remote.shell_cmd("input keyevent #{back_key}")

    # get screenshot
    screenshot_file = "#{device_id}.png"
    remote.take_screenshot(screenshot_file)
    success = File.exists?(screenshot_file)
    stdout_log.info "Device #{device_id} screenshot done: #{success ? 'Success' : 'Failed'}"
    fail "Screenshot doesn't exists on disk!" unless success
    results << [:success, device_id, nil]
  rescue Exception => e
    results << [:failed, device_id, e]
    stdout_log.error "Thread#{thread_index}, device #{device_id} failed: #{e}. backtrace:#{e.backtrace}"
  end
end

results_array = []
results_array << results.pop while results.size > 0

stdout_log.info 'all done'
stdout_log.info "Passed: #{results_array.count{|item| item.first == :success}}"
stdout_log.info "failed: #{results_array.count{|item| item.first == :failed}}"