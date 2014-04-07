require 'rspec'
require 'testdroidhelper'

describe TestdroidHelper::RemoteConnectionProvider do
  let(:remote_connection_provider) do
    username = "str_username"
    password = "str_passwd"
    Testdroid::Cloud::Client.stub(:new)
    Testdroid::Cloud::Client.should_receive(:new).with(username, password, TD_HOST, TD_USERS_HOST).and_call_original
    Testdroid::Cloud::Client.any_instance.stub(:get_user).and_return("User")
    TestdroidHelper::RemoteConnectionProvider.new username, password
  end
  describe "#new" do
    it "Returns a RemoteConnectionProvider" do
      remote_connection_provider.should be_an_instance_of TestdroidHelper::RemoteConnectionProvider
    end
  end
  describe "#setup_test" do
    it "fails, bad app path" do
      TestdroidHelper::RemoteConnection.any_instance.stub(:setup_project)
      project_name = "mock_project"
      test_app_path = "bad_test_app_path"
      selected_devices = [1,2,3]
      target_concurrency = 5
      expect{remote_connection_provider.setup_test(project_name, test_app_path, selected_devices, target_concurrency)}.to raise_exception
    end
  end
  describe "#get_device" do
    let(:target_concurrency) {5}
    before :each do
      TestdroidHelper::RemoteConnection.any_instance.stub(:setup_project)
      TestdroidHelper::RemoteConnection.any_instance.stub(:install_app)
      TestdroidHelper::RemoteConnection.any_instance.stub(:start_run).and_return("Project_Run")
      project_name = "mock_project"
      test_app_path = "bad_test_app_path"
      selected_devices = (0..20).to_a
      remote_connection_provider.setup_test(project_name, test_app_path, selected_devices, target_concurrency)
    end
    it "Get some devices" do
      remote_connection_provider.instance_variable_get(:@remote_connect).stub(:connect_to_device).with("Project_Run", an_instance_of(Fixnum)).and_return("Remote")
      threads = []
      devices = Queue.new
      1.upto(target_concurrency - 1) do |i|
        threads << Thread.new do
          devices << remote_connection_provider.get_device(i)
        end
      end
      sleep 0.5
      devices.size.should eql(0) # Running in batches, no devices should be given until enough queued devices
      devices << remote_connection_provider.get_device(5)
      threads.each { |t| t.join }
    end
  end
end
