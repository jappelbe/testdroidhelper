# Stomp writes into stderr. Redirect to logs
class StderrRedirect

  # @param [Logger] logger
  # @param [Regexp] Filter for messages which should not be shown in in STDERR
  def initialize(logger, filter)
    @logger = logger
    @filter = filter
  end
  def method_missing(method, *args)
    STDERR.method(method).call(*args)
  end
  def print(msg)
    if msg.match(@filter)
      @logger.info "STDERR: #{msg}" if @logger
    else
      STDERR.print(msg)
    end
  end
  def write(msg)
    self.print(msg)
  end
end