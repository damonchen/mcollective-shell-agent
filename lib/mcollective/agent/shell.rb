require 'mcollective/agent/shell/job'

module MCollective
  module Agent
    class Shell<RPC::Agent
      action 'run' do
        run_command(request.data)
      end

      action 'start' do
        start_command(request.data)
      end

      action 'status' do
        handle = request[:handle]
        process = Job.new(handle)
        stdout_offset = request[:stdout_offset] || 0
        stderr_offset = request[:stderr_offset] || 0

        reply[:status] = process.status
        reply[:stdout] = process.stdout(stdout_offset)
        reply[:stderr] = process.stderr(stderr_offset)
        if process.status == :stopped
          reply[:exitcode] = process.exitcode
        end
      end

      action 'kill' do
        handle = request[:handle]
        job = Job.new(handle)

        job.kill
      end

      action 'list' do
        list
      end

      private

      def run_command(request = {})
        process = Job.new

        if request[:type] == 'cmd' or request[:type].nil?
          process.start_command(request[:command])
        elsif request[:type] == 'script'
          script_path = gen_tmpfile(request)
          script_path = "su - #{request[:user]} -c '" + script_path + " " + request[:params].to_s + "'" if !windows? and request[:user]
          process.start_command(script_path + " " + request[:params].to_s)
          end
        end
        timeout = request[:timeout] || 0
        reply[:success] = true
        begin
          Timeout::timeout(timeout) do
            process.wait_for_process
          end
        rescue Timeout::Error
          reply[:success] = false
          process.kill
        end

        reply[:stdout] = process.stdout
        reply[:stderr] = process.stderr
        reply[:exitcode] = process.exitcode
        process.cleanup_state
      end

      def start_command(request = {})
        job = Job.new
        if request[:type] == 'cmd'
          job.start_command(request[:command])
        elsif request[:type] == 'script'
          script_path = gen_tmpfile(request)
          script_path = "su - #{request[:user]} -c '" + script_path + " " + request[:params].to_s + "'" if !windows? and request[:user]
          job.start_command(script_path + " " + request[:params].to_s)
        end

        reply[:handle] = job.handle
      end

      def list
        list = {}
        Job.list.each do |job|
          list[job.handle] = {
            :id      => job.handle,
            :command => job.command,
            :status  => job.status,
            :signal  => job.signal,
          }
        end

        reply[:jobs] = list
      end
    end

    def gen_tmpfile(request)
      require 'tempfile'
      tmpfile = Tempfile.new(request[:filename])
      if request[:base64] == true
        content = Base64.decode64(request[:content])
      else
        content = request[:content]
      end
      content = content.encode('gbk') if windows?
      tmpfile.write(content)
      tmpfile.chmod(0755)
      tmpfile.close
      if windows?
        if request[:filename].match(/\./)
          script_path = (tmpfile.path + "." + request[:filename].split(/\./)[-1]).encode('gbk')
          File.rename tmpfile.path,script_path
        else
          script_path = tmpfile.path
        end
        script_path
      else
        tmpfile.path
      end
    end

    def windows?
      RUBY_PLATFORM.match(/cygwin|mswin|mingw|bccwin|wince|emx|win32|dos/)
    end
  end
end
