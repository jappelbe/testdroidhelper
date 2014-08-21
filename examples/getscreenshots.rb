require 'logger'
require 'bundler'
Bundler.setup(:default, :rake)
require 'testdroidhelper'

raise ArgumentError.new("(Only got #{ARGV.count} params, 4 required) Usage: #{$0} <username> <password> <project_name> <test_app_path>") unless ARGV.count == 4
USERNAME, PASSWORD, PROJECT_NAME, TEST_APP_PATH = ARGV
CONCURRENCY = 50 # target_concurrency should be smaller than thread count
THREAD_COUNT = 100

INCL_DEV_FILTER = /Nexus/i
EXCL_DEV_FILTER = /(iphone|ipad|apple|ipod)/i

stdout_log = Logger.new($stdout)

alt_logger = Logger.new("altlog.log")

stdout_log.info('Setting up RemoteConnectionProvider')
td_provider = TestdroidHelper::RemoteConnectionProvider.new(USERNAME, PASSWORD, alt_logger)

stdout_log.info('Selecting devices')
device_ids_array = td_provider.get_devices_array(INCL_DEV_FILTER, EXCL_DEV_FILTER)
device_ids_array.map! {|dev| dev.first}


raise "No devices left after filtering!" if device_ids_array.empty?

 CONCURRENCY = [CONCURRENCY , device_ids_array.count].min  

stdout_log.info("Setting up test (#{device_ids_array.count} devices) for #{CONCURRENCY} threads")
td_provider.setup_test(PROJECT_NAME, TEST_APP_PATH, device_ids_array, CONCURRENCY)
stdout_log.info("Setting up done")
td_provider.execute_on_all_devices(THREAD_COUNT) do |remote, device_id, thread_index|
  begin
    device_name = td_provider.get_device_name(device_id)
    stdout_log.info "Thread#{thread_index}, rolled device with id = '#{device_id}', name = '#{device_name}'"
    screenshot_file = "#{device_id}.png"
    remote.take_screenshot(screenshot_file)
    success = File.exists?(screenshot_file)
    stdout_log.info "Device #{device_id} screenshot done: #{success ? 'Success' : 'Failed'}"
    fail "Screenshot doesn't exists on disk!" unless success
  rescue Exception => e
    stdout_log.error "Thread#{thread_index}, device #{device_id} failed: #{e}. backtrace:#{e.backtrace}"
  end
end

stdout_log.info 'all done'
stdout_log.info td_provider.device_statuses