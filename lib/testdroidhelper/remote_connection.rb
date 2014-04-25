module TestdroidHelper

  class RemoteConnection
    # @param [String] username
    # @param [String] password
    # @param [Logger] logger (optional)
    def initialize(username, password, logger=Logger.new(STDOUT))
      @username = username
      @password = password
      @td_logger = logger

      # stomp outputs to stderr, we'd rather have that in file
      stomp_filter = /connection.receive returning EOF as nil.*resetting connection/
      $stderr = StderrRedirect.new(nil, stomp_filter)

      @cloud = Testdroid::Cloud::Client.new(@username, @password, TestdroidHelper::TD_HOST, TestdroidHelper::TD_USERS_HOST)

      @user = @cloud.get_user
      raise StandardError.new("Couldn't login with as user '#{@username}'") unless @user
      @connect_mutexes = {}
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
      raise StandardError.new("Empty array provided, will not start") if devices_array.empty?
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
    def connect_to_device(project_run, device_id, timeout=TestdroidHelper::TD_DEFAULT_TIMEOUT)
      remote = nil
      requested_device = nil

      connection_hash = {login: @username,
                         passcode: @password,
                         host: TestdroidHelper::TD_HOST,
                         port: TestdroidHelper::TD_PORT,
                         ssl: TestdroidHelper::TD_SSL}
      stomp_hash = {hosts: [connection_hash],
                    parse_timeout: 150,
                    logger: @td_logger}

      # Connection mutex is project-run specific
      @connect_mutexes[project_run.id] ||= Mutex.new
      @connect_mutexes[project_run.id].synchronize do
        Timeout.timeout(timeout) do
          begin
            remote = Testdroid::Cloud::Remote.new(stomp_hash)
            remote.open
            @td_logger.debug "TestdroidHelper::RemoteConnection.connect_to_device wait until project is running"
            sleep(5) until  @project.runs.get(project_run.id).group_state == 'RUNNING' || @project.runs.get(project_run.id).group_state == 'FINISHED'
            device_runs = @project.runs.get(project_run.id).device_runs.list
            @td_logger.warn "TestdroidHelper::RemoteConnection.connect_to_device project run started with more than one device - device runs: #{device_runs.size}" unless device_runs.size == 1
            requested_devices = device_runs.select {|dev| dev.device_id == device_id.to_i}
            requested_device = requested_devices.first
            @td_logger.debug "TestdroidHelper::RemoteConnection.connect_to_device device:'#{device_id}' state: #{requested_device.group_state}" unless requested_device.nil?
          rescue TimeoutError => e
            raise TimeoutError.new("Timeout while opening remote to device '#{device_id}': #{e}")
          end
        end
      end
      raise StandardError.new('No device could be selected') unless requested_device
      raise StandardError.new('Device is excluded or test run is canceled') if requested_device.group_state == 'FINISHED' 
      remote.wait_for_connection(project_run.id, requested_device.id)
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
