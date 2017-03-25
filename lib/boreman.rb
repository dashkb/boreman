require "boreman/version"

module Boreman
  def self.run(action, selector, opts = {})
    self.send action, selector, opts
  end

  def self.procfile_path
    @procfile_path ||= "#{app_dir}/Procfile"
  end

  # assumes command is run from in a git directory with a Procfile
  # TODO walk upwards from cwd looking for Procfile
  def self.app_dir
    @app_dir ||= ENV['BOREMAN_APP_DIR'] || `git rev-parse --show-toplevel`.chomp
  end

  def self.read_procfile
    File.read(procfile_path).lines.each_with_object({}) do |line, procs|
      if m = /^(\w+):(.+)$/.match(line)
        procs[m[1]] = m[2]
      end
    end
  end

  def self.procs
    @procs ||= read_procfile
  end

  # directory for keeping track of pid/status for this process
  def self.proc_dir(selector)
    base = ENV['BOREMAN_PROC_DIR'] || "#{app_dir}/.boreman"

    "#{base}/#{selector}".tap do |dir|
      `mkdir -p #{dir}`
    end
  end

  def self.pidfile(selector)
    "#{proc_dir selector}/pid"
  end

  def self.pid(selector)
    should_be_running?(selector) and File.read(pidfile(selector))
  end

  def self.should_be_running?(selector)
    File.exists? pidfile(selector)
  end

  def self.is_running?(selector)
    if id = pid(selector)
      !`ps -o pid= #{id}`.chomp.empty?
    else
      false
    end
  end

  def self.write_pid(selector, pid)
    File.write(pidfile(selector), pid)
  end

  def self.prepare_command(cmd)
    cmd.gsub(/\$([0-9A-Z_]+)/) do |var, v2|
      ENV[$1]
    end
  end

  #
  # Actions
  #

  def self.start(selector, opts)
    if should_be_running?(selector)
      puts "#{selector} should already be running, deal with that first"
      return
    end

    if cmd = procs[selector]
      cmd = prepare_command(cmd)

      pid = Process.spawn(cmd)
      Process.detach(pid)
      write_pid selector, pid
      puts "Started #{selector}, pid = #{pid}"
    else
      puts "Entry #{selector} not found in Procfile"
    end
  end

  def self.restart(selector, opts)
    if is_running?(selector)
      stop selector, opts
    elsif should_be_running?(selector)
      puts "#{selector} should have been running but wasn't... 'restarting' anyway"
      `rm #{pidfile(selector)}`
    end

    start selector, opts
  end

  def self.stop(selector, opts)
    if !is_running?(selector)
      puts "#{selector} is not currently running"
      return
    end

    id       = pid(selector).to_i
    attempts = 0

    while is_running?(selector)
      attempts += 1
      if attempts > 5
        puts "attempt number #{attempts}; using KILL"
        signal = 'KILL'
      else
        signal = 'TERM'
      end

      Process.kill(signal, id) rescue
      sleep attempts
    end

    `rm #{pidfile(selector)}`
    puts "Stopped #{selector} #{id}"
  end
end
