module TestdroidHelper

  # Will provide a continuous flow of remotes by creating new projects
  class RemoteConnectionProvider
    # @param [String] username
    # @param [String] password
    def initialize(username, password, logger=Logger.new(STDOUT))
      @logger = logger
      @remote_connect = TestdroidHelper::RemoteConnection.new(username, password, @logger)
    end

    # @param [String] project_name
    # @param [String] test_app_path
    # @param [Array<String, Fixnum>] selected_devices
    # @param [Fixnum] target_concurrency (optional)
    def setup_test(project_name, test_app_path, selected_devices, target_concurrency=TestdroidHelper::TD_DEFAULT_TARGET)
      @target = target_concurrency
      @devices_to_go = Set.new(selected_devices)
      @devices_waiting = Queue.new
      @project_dev_id = {}
      selected_devices.each {|dev|
        @project_dev_id[dev] = Queue.new
      }
      @new_project_run_mutex = Mutex.new
      @remote_connect.setup_project(project_name)
      @remote_connect.install_app(test_app_path)
    end

    def device_done(dev_id)

    end

    # @param [Fixnum, String] device_id
    # @return [Testdroid::Cloud::Remote] remote (connected to device)
    def get_device(device_id)
      @devices_waiting << device_id
      @new_project_run_mutex.synchronize{
        if @devices_waiting.size >= @target or @devices_to_go.size < @target
          devices_to_run_here_count = [@devices_waiting.size, @devices_to_go.size].min
          device_array = []
          devices_to_run_here_count.times do
            device_to_run = @devices_waiting.pop
            device_array << device_to_run
            @devices_to_go.delete(device_to_run)
          end
          project_run = @remote_connect.start_run(device_array)
          device_array.each do |dev|
            @project_dev_id[dev] << project_run
          end
        end
      }
      current_project_run = @project_dev_id[device_id].pop
      this_remote = @remote_connect.connect_to_device(current_project_run, device_id)
    end

    def get_devices_array(filter_include=/.*/i, filter_exclude=nil)
      devices = @remote_connect.get_devices
      devices.select! {|dev| dev.user_name.match(filter_include)}
      devices.select! {|dev| dev.user_name.match(filter_exclude) ? false : true } if filter_exclude
      devices.map! { |dev| [dev.id, dev.user_name, dev.serial_id] }
      devices
    end

    def get_device_name(device_id)
      device = @remote_connect.get_devices.select { |dev| dev.id.to_i == device_id.to_i }.first
      device.user_name
    end

    def get_devices_string
      @remote_connect.get_devices.map { |dev| "#{dev.user_name} ID: #{dev.id} serialId: #{dev.serial_id}" }.join("\n")
    end

    def get_project_names
      projects = @remote_connect.get_projects
      projects.map {|p| p.name}
    end

    def execute_on_all_devices(thread_count)
      device_ids = Queue.new
      @devices_to_go.each { |dev| device_ids << dev }

      threads = []
      1.upto(thread_count) do |idx|
        threads << Thread.new do
          get_device = lambda  do |device_queue|
            return nil if device_queue.empty?
            device = device_queue.pop(true) rescue ThreadError # pop(true) -> Non blocking pop
            device == ThreadError ? nil : device
          end
          while (device_id = get_device.call(device_ids))
            remote = self.get_device(device_id)
            yield remote, device_id, idx
            remote.close
          end
        end
      end
      threads.each { |t| t.join }
    end
  end
end