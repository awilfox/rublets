require 'fileutils'

class Sandbox
  attr_accessor :time, :path, :home, :extension, :script_filename, :evaluate_with, :timeout, :owner, :includes, :code, :output_limit_before_gisting, :binaries_must_exist

  def initialize(options = {})
    unless ENV['PATH'].split(':').any? { |path| File.exists? path + '/sandbox' }
      raise "The `sandbox` executable does not exist and is required."
    end
    
    unless ENV['PATH'].split(':').any? { |path| File.exists? path + '/timeout' }
      raise "The `timeout` executable does not exist and is required. (Is coreutils installed?)"
    end
    
    @time = Time.now
    @path = options[:path]
    @home = options[:home] || "#{@path}/sandbox_home-#{@time.to_f}"
    @extension = options[:extension] || "txt"
    @script_filename = options[:script] || "#{@time.to_f}.#{@extension}"
    @evaluate_with = options[:evaluate_with]
    @timeout = options[:timeout].to_i || 5
    @owner = options[:owner] || 'anonymous'
    @includes = options[:includes] || []
    @code = options[:code]
    @output_limit_before_gisting = 2
    @binaries_must_exist = options[:binaries_must_exist] || [@evaluate_with.first]

    FileUtils.mkdir_p @home
    FileUtils.mkdir_p "#{@path}/evaluated"
    FileUtils.mkdir_p "#{@path}/tmp"
  end

  def mkdir(directory)
    FileUtils.mkdir_p "#{@home}/#{directory}"
  end

  def copy(source, destination)
    FileUtils.cp_r source, "#{@home}/#{destination}"
  end

  def evaluate
    "One of (#{@binaries_must_exist.join(', ')}) was not found in $PATH. Try again later." and return unless binaries_all_exist?
    insert_code_into_file
    copy_audit_script
    IO.popen(['sandbox', '-H', @home, '-T', "#{@path}/tmp/", '-t', 'sandbox_x_t', 'timeout', @timeout.to_s, *@evaluate_with, @script_filename, :err => [:child, :out]]) { |stdout|
      @result = stdout.read
    }
    if $?.exitstatus.to_i == 124
      @result = "Timeout of #{@timeout} seconds was hit."
    elsif @result.empty?
      @result = "No output." 
    end
    
    lines, output = @result.split("\n"), []
    if lines.any? { |l| l.length > 255 }
      output << "<output is long> #{gist}"
    else
      lines[0...@output_limit_before_gisting].each do |line|
        output << line
      end
      if lines.count > @output_limit_before_gisting
        output << "<output truncated> #{gist}"
      end
    end
    output
  end

  def rm_home!
    FileUtils.rm_rf @home
  end

  def gist
    gist = URI.parse('https://api.github.com/gists')
    http = Net::HTTP.new(gist.host, gist.port)
    http.use_ssl = true
    response = http.post(gist.path, {
        'public' => false,
        #'description' => "#{nickname}'s ruby eval",
        'files' => {
          'input.rb' => {
            'content' => File.open("#{@home}/#{@script_filename}").read
          },
          'output.txt' => {
            'content' => @result
          }
        }
      }.to_json)
    if response.response.code.to_i != 201
      return "Unable to Gist output."
    else
      JSON(response.body)['html_url']
    end
  end

  private
  def copy_audit_script
    FileUtils.cp("#{@home}/#{@script_filename}", "#{@path}/evaluated/#{@time.year}-#{@time.month}-#{@time.day}_#{@time.hour}-#{@time.min}-#{@time.sec}-#{@owner}-#{@time.to_f}.#{@extension}")
  end

  def binaries_all_exist?
    binaries = []
    binaries << ENV['PATH'].split(':').any? { |path| File.exists? path + '/' + @evaluate_with.first }
    !binaries.include? false
  end

  def insert_code_into_file
    File.open("#{@home}/#{@time.to_f}.#{@extension}", 'w') do |f|
      f.puts @code
    end
  end

end