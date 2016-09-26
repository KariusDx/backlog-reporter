#
# Copyright (C) 2016 Conjur Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
require "backlog_reporter/version"
require "backlog_reporter/railtie" if defined? Rails
require 'rest-client'
require 'multi_json'
require 'puma'

class BacklogReporter
  def initialize flag_path, token, max_backlog = 16
    @token = token
    @flag = FlagFile.new flag_path
    @max_backlog = max_backlog
  end

  def log level, msg=nil
    if !msg
      msg = level
      level = 'info'
    end

    if defined?(Rails)
      Rails.logger.send(level, 'BacklogReporter: ' + msg)
    else
      puts('BacklogReporter: ' + msg)
    end
  end

  def check_http
    begin
      resp = RestClient.get("http://127.0.0.1:9293/stats?token=#{@token}", {accept: :json})
    rescue => ex
      log 'error', ex.to_s
      return
    end

    backlogs = MultiJson.load(resp.body)["worker_status"].map {|status|
       backlog = status['last_status']['backlog'] || 0
       if backlog > 0
	 "PID #{status['pid']}: #{backlog}"
       end
       }.compact

    if backlogs.length > 0
      log(backlogs.join(', '))
    end
  end

  def check
    if server = puma_server
      log server.backlog.to_s
      @flag.set server.backlog > @max_backlog
    end
  end

  ThreadLocalKey = :puma_server

  def puma_server
    puma_thread = Thread.list.find{|t| t[ThreadLocalKey]}
    puma_thread && puma_thread[ThreadLocalKey]
  end

  def check_periodically interval_s = 0.01
    while true
      begin
        check_http
        check
      rescue => ex
        log 'error', ex.to_s
      end

      sleep interval_s                                                                                                                   
    end                                                                                                                                  
  end

  def check_in_background interval_s = 0.01                                                                                              
    @thread = Thread.new { check_periodically interval_s }                                                                               
  end

  def stop
    if @thread
      @thread.exit
      @thread.join
      @thread = nil
    end
  end

  class FlagFile
    def initialize path
      @path = path
      @exists = File.exists? path
      set false
    end

    def set value
      if @exists != value
        FileUtils.send((value ? :touch : :rm_f), @path)
        @exists = value
      end
    end
  end
end
