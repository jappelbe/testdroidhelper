module TestdroidHelper

  # Will provide a continuous flow of remotes by creating new projects
  class RemoteConnectionProvider
    attr_reader :device_statuses
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
      @device_statuses = {}
      @remote_connect.setup_project(project_name)
      @remote_connect.install_app(test_app_path)
    end

    def device_done(dev_id)

    end

    # @param [Fixnum, String] device_id
    # @return [Testdroid::Cloud::Remote] remote (connected to device)
    def get_device(device_id)
      @devices_waiting << device_id
      @device_statuses[device_id] = :requested
      @new_project_run_mutex.synchronize{
        break unless @devices_to_go.size > 0
        break unless (@devices_waiting.size >= @target or @devices_to_go.size == @devices_waiting)
        devices_to_run_here_count = [@devices_waiting.size, @devices_to_go.size, @target].min
        device_array = []
        devices_to_run_here_count.times do
          device_to_run = @devices_waiting.pop
          device_array << device_to_run
          @devices_to_go.delete(device_to_run)
        end
        retried_already = false
        begin
          project_run = @remote_connect.start_run(device_array)
        rescue Exception => e
          @logger.warn "TestdroidHelper::RemoteConnectionProvider.get_device(#{device_id.inspect}): Couldn't start project_run: #{e}"
          @logger.warn "backtrace: #{e}"
          puts "***** COULD NOT START PROJECT RUN! CHECK LOGS!"
          unless retried_already
            @logger.warn "retrying once"
            retry
          end
          @logger.warn "Already retried, giving up, these devices will not be run!"
        end
        device_array.each do |dev|
          @project_dev_id[dev] << project_run
        end
      }
      current_project_run = @project_dev_id[device_id].pop
      @device_statuses[device_id] = :project_run_started
      this_remote = nil
      begin
        this_remote = @remote_connect.connect_to_device(current_project_run, device_id)
        @device_statuses[device_id] = :remote_connected
      rescue StandardError => e
        @logger.warn "TestdroidHelper::RemoteConnectionProvider.get_device(#{device_id}): couldn't be connected: #{e}"
        @device_statuses[device_id] = "#{e}".to_sym
      end
      this_remote
    end

    def get_devices_array(filter_include=/.*/i, filter_exclude=nil)
      devices = @remote_connect.get_devices
      devices.select! {|dev| dev.display_name.match(filter_include)}
      devices.select! {|dev| dev.display_name.match(filter_exclude) ? false : true } if filter_exclude
      devices.map! { |dev| [dev.id, dev.display_name, dev.os_type] }
      devices
    end

    def get_device_name(device_id)
      device = @remote_connect.get_devices.select { |dev| dev.id.to_i == device_id.to_i }.first
      device.display_name
    end

    def get_devices_string
      @remote_connect.get_devices.map { |dev| "#{dev.display_name} ID: #{dev.id} os type: #{dev.serial_id}" }.join("\n")
    end

    def get_project_names
      projects = @remote_connect.get_projects
      projects.map {|p| p.name}
    end

    def execute_on_all_devices(thread_count)
      device_ids = Queue.new
      @devices_to_go.to_a.shuffle.each { |dev| device_ids << dev }

      threads = []
      1.upto(thread_count) do |idx|
        threads << Thread.new do
          get_device = lambda  do |device_queue|
            return nil if device_queue.empty?
            device = device_queue.pop(true) rescue ThreadError # pop(true) -> Non blocking pop
            device == ThreadError ? nil : device
          end
          while (device_id = get_device.call(device_ids))
            @logger.info "Thread#{idx} requesting device #{device_id}. #{device_ids.size} devices to go."
            remote = self.get_device(device_id)
            unless remote
              @logger.warn "#device #{device_id} cannot be used for testing as it is nil"
              next
            end
            yield remote, device_id, idx
            remote.close
            @device_statuses[device_id] = :remote_closed
          end
          threads_alive = threads.map {|t| t.alive?}.count(true)
          @logger.info "Thread#{idx} is done! #{threads_alive} threads to go"
        end
      end
      threads.each { |t| t.join }
    end
  end
end