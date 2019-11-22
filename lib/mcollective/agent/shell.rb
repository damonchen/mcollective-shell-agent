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
        environment = get_environment(request)
        process.start_command(environment, gen_command(request))
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

        begin
          reply[:stdout] = process.stdout.encode("utf-8", bom_encoding(process.stdout))
        rescue
          reply[:stdout] = process.stdout
        end

        begin
          reply[:stderr] = process.stderr.encode("utf-8", bom_encoding(process.stderr))
        rescue
          reply[:stderr] = process.stderr
        end

        reply[:exitcode] = process.exitcode
        process.cleanup_state
      end

      def start_command(request = {})
        job = Job.new
        environment = get_environment(request)
        job.start_command(environment, gen_command(request))
        reply[:handle] = job.handle
      end

      def list
        list = {}
        Job.list.each do |job|
          list[job.handle] = {
              :id => job.handle,
              :command => job.command,
              :status => job.status,
              :signal => job.signal,
          }
        end

        reply[:jobs] = list
      end

      def gen_tmpfile(request = {})
        require 'tempfile'
        tmpfile = Tempfile.new(request[:filename])
        if request[:base64]
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
            script_path = (tmpfile.path + '.' + request[:filename].split(/\./)[-1]).encode('gbk')
            File.rename tmpfile.path, script_path
          else
            script_path = tmpfile.path
          end
          script_path
        else
          tmpfile.path
        end
      end

      def get_environment(request = {})
        environment = request[:environment] || '{}'

        if windows?
          export = 'set'
          eol = '\r\n'
        else
          export = 'export'
          eol = ';'
        end

        JSON.parse(environment).map{|k,v|
          "#{export} #{k}=\'#{v}'"
        }.join(eol) + " "
      end

      def gen_command(request = {})
        if request[:type] == 'cmd'
          cmd = request[:command]
          if windows?
            # 暂不支持windows下账户切换操作
            "cmd /C " + cmd
          else
            if request[:user]
              "su - #{request[:user]} - c " + cmd
            else
              cmd
            end
          end
        else
          cmd = [gen_tmpfile(request),request[:params].to_s.force_encoding("utf-8").encode(Encoding.default_external)].join(" ")
          if windows?
            # 暂不支持windows下账户切换操作
            [get_script_type(request), cmd].join(" ")
          else
            if request[:user]
              ["su - #{request[:user]} - c", get_script_type(request), cmd].join(" ")
            else
              [get_script_type(request), cmd].join(" ")
            end
          end
        end
      end

      def get_script_type(request = {})
        if request[:scriptType].to_s == ''
          windows? ? "cmd /C" : "sh"
        else
          script_map = {
            "Shell" => "sh",
            "Python" => "python",
            "Bat" => "cmd /C",
          }
          script_map[request[:scriptType]]
        end
      end

      def windows?
          RUBY_PLATFORM.match(/cygwin|mswin|mingw|bccwin|wince|emx|win32|dos/)
      end

      def bom_encoding(str)
        return "UTF-8" if str.to_s == ''
        if str.encoding.name == "ASCII-8BIT"
          first = str[0].to_s.unpack('H*')
          second = str[1].to_s.unpack('H*')
          third = str[2].to_s.unpack('H*')
          fourth = str[3].to_s.unpack('H*')
          if [first, second, third].join == 'efbbbf'
            'UTF-8'
          elsif ['fffe', 'feff'].include? [first, second].join
            'UTF-16'
          elsif [first, second, third, fourth].join == '0000feff'
            'UTF-32'
          else
            Encoding.default_external
          end
        else
          str.encoding.name
        end
      end
    end
  end
end