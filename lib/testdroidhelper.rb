#require "testdroidhelper/version"
require 'logger'
require 'timeout'
require 'thread'

original_verbosity = $VERBOSE
$VERBOSE = nil
require 'testdroid-cloud'
require 'testdroid-cloud-remote'
$VERBOSE = original_verbosity

module TestdroidHelper

  TD_HOST = 'cloud.testdroid.com'
  TD_USERS_HOST = 'https://users.testdroid.com'
  TD_PORT = 61612
  TD_SSL = true
  TD_DEFAULT_TIMEOUT = 60 * 60 * 60 #1h

  TD_DEFAULT_TARGET = 5

end

require 'testdroidhelper/remote_connection.rb'
require 'testdroidhelper/remote_connection_provider.rb'