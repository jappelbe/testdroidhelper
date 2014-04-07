#require "testdroidhelper/version"
require 'logger'
require 'timeout'
require 'thread'

original_verbosity = $VERBOSE
$VERBOSE = nil
require 'testdroid-cloud'
require 'testdroid-cloud-remote'
$VERBOSE = original_verbosity

TD_HOST = 'cloud.testdroid.com'
TD_USERS_HOST = 'https://users.testdroid.com'
TD_PORT = 61612
TD_SSL = true
TD_DEFAULT_TIMEOUT = 60 * 60 * 60 #1h

TD_DEFAULT_TARGET = 10

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
    def setup_test(project_name, test_app_path, selected_devices, target_concurrency=TD_DEFAULT_TARGET)
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

  class RemoteConnection
    # @param [String] username
    # @param [String] password
    # @param [Logger] logger (optional)
    def initialize(username, password, logger=Logger.new(STDOUT))
      @username = username
      @password = password
      @td_logger = logger
      @cloud = Testdroid::Cloud::Client.new(@username, @password, TD_HOST, TD_USERS_HOST)

      @user = @cloud.get_user
      raise StandardError.new("Couldn't login with as user '#{@username}'") unless @user
      @connect_mutex = Mutex.new
    end

    def setup_project(project_name)
      @project = @user.projects.list.detect {|p| p.name == project_name}
      raise ArgumentError.new("project '#{project_name}' not found") unless @project
    end

    # @param [Array<String>] devices_array
    # @param [Numeric] timeout
    # @return [TestdroidAPI::Run] project_run
    def start_run(devices_array, timeout = nil)
      raise StandardError.new('Project has not been setup yet, call .setup_project') unless @project
      project_run = nil
      begin
        csv_devices_list = nil
        Timeout.timeout(timeout) do
          csv_devices_list = devices_array.join(',')
          project_run = @project.run(nil, false, csv_devices_list)
        end
      rescue TimeoutError => e
        raise TimeoutError.new("Timeout when starting testrun. #{e}")
      end
      raise StandardError.new("TestdroidHelper::RemoteConnection.start_run: Couldn't create a project run") unless project_run
      project_run
    end

    # @param [TestdroidApi::Run] project_run
    # @param [Fixnum] device_id
    # @param [Numeric] timeout
    def connect_to_device(project_run, device_id, timeout=TD_DEFAULT_TIMEOUT)
      remote = nil
      requested_device = nil
      connection_hash = {login: @username,
                         passcode: @password,
                         host: TD_HOST,
                         port: TD_PORT,
                         ssl: TD_SSL}
      stomp_hash = {hosts: [connection_hash],
                    parse_timeout: 150,
                    logger: @td_logger}
      @connect_mutex.synchronize do
        Timeout.timeout(timeout) do
          begin
            remote = Testdroid::Cloud::Remote.new(stomp_hash)
            remote.open
            device_runs = @project.runs.get(project_run.id).device_runs.list
            @td_logger.debug "TestdroidHelper::RemoteConnection.connect_to_device '#{device_id}': device_runs=#{device_runs}. "
            requested_devices = device_runs.select {|dev| dev.device_id == device_id}
            requested_device = requested_devices.first
          rescue TimeoutError => e
            raise TimeoutError.new("Timeout while opening remote to device '#{device_id}': #{e}")
          end
        end
      end
      raise StandardError.new('No device could be selected') unless requested_device
      success = remote.wait_for_connection(project_run.id, requested_device.id)
      return nil unless success
      remote
    end

    def install_app(app)
      path = Pathname.new(app)
      raise StandardError.new("'#{app}' doesn't exists") unless path.exist?
      case path.extname.downcase.strip
        when /apk/
          @project.uploadAPK(app)
        else
          raise StandardError.new("Only apk files supported for now, app was '#{app}'")
      end
      @project.uploadAPK(app)
    end

    def get_devices
      @user.devices.list
    end

    def get_projects
      @user.projects.list
    end

  end
end