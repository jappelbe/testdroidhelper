require 'rspec'
require 'testdroidhelper'

describe TestdroidHelper::RemoteConnection do
  before :each do
    username = "str_username"
    password = "str_passwd"
    Testdroid::Cloud::Client.stub(:new)
    Testdroid::Cloud::Client.should_receive(:new).with(username, password, TestdroidHelper::TD_HOST, TestdroidHelper::TD_USERS_HOST).and_call_original
    Testdroid::Cloud::Client.any_instance.stub(:get_user).and_return("User")
    @remote_connection = TestdroidHelper::RemoteConnection.new username, password
  end
  describe "#new" do
    it "Returns a RemoteConnection" do
      @remote_connection.should be_an_instance_of TestdroidHelper::RemoteConnection
    end
  end
end
