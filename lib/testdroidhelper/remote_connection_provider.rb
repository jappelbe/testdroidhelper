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
      @devices_to_go = Queue.new
      @devices_waiting = Queue.new
      @project_dev_id = {}
      selected_devices.each {|dev|
        @devices_to_go << dev
        @project_dev_id[dev] = Queue.new
      }
      @new_project_run_mutex = Mutex.new
      @remote_connect.setup_project(project_name)
      @remote_connect.install_app(test_app_path)
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
            device_array << @devices_waiting.pop
          end
          project_run = @remote_connect.start_run(device_array)
          device_array.each do |dev|
            @project_dev_id[dev] << project_run
          end
        end
      }
      project = @project_dev_id[device_id].pop
      this_remote = @remote_connect.connect_to_device(project, device_id)
    end

    def get_devices_array
      @remote_connect.get_devices.map {|dev| [dev.id, dev.user_name, dev.serial_id] }
    end

    def get_devices_string
      @remote_connect.get_devices.map {|dev| "#{dev.user_name} ID: #{dev.id} serialId: #{dev.serial_id}" }.join("\n")
    end

    def get_project_names
      projects = @remote_connect.get_projects
      projects.map {|p| p.name}
    end
  end
end