require_relative 'runner_service_statefull'
require_relative 'runner_service_stateless'
require 'json'

class ImageBuilder

  def initialize(src_dir, args)
    @src_dir = src_dir
    @args = args
  end

  def build_and_test_image
    if test_framework?
      check_start_point_can_be_created
    end
    build_the_image
    if test_framework?
      check_start_point_src_red_green_amber_using_runner_stateless
      check_start_point_src_red_green_amber_using_runner_statefull
    end
    image_name
  end

  private

  def check_start_point_can_be_created
    # TODO: Try the curl several times before failing?
    banner
    script = 'cyber-dojo'
    url = "https://raw.githubusercontent.com/cyber-dojo/commander/master/#{script}"
    assert_system "curl --silent -O #{url}"
    assert_system "chmod +x #{script}"
    name = 'start-point-create-check'
    system "./#{script} start-point rm #{name} &> /dev/null"
    assert_system "./#{script} start-point create #{name} --dir=#{src_dir}"
  end

  # - - - - - - - - - - - - - - - - -

  def build_the_image
    banner
    assert_system "cd #{src_dir}/docker && docker build --tag #{image_name} ."
  end

  # - - - - - - - - - - - - - - - - -

  def check_start_point_src_red_green_amber_using_runner_stateless
    banner
    if manifest['runner_choice'] == 'stateful'
      puts "manifest.json ==> 'runner_choice':'stateful'"
      puts 'skipping'
      return
    end
    assert_timed_run_stateless(:red)
    assert_timed_run_stateless(:amber)
    assert_timed_run_stateless(:green)
  end

  def assert_timed_run_stateless(colour)
    runner = RunnerServiceStateless.new
    args = [image_name]
    args << kata_id
    args << 'salmon'
    args << all_files(colour)
    args << (max_seconds=10)
    took,sss = timed { runner.run(*args) }
    assert_rag(colour, sss, "dir == #{start_point_dir}")
    puts "#{colour}: OK (~#{took} seconds)"
  end

  def all_files(colour)
    files = start_files
    if colour != :red
      filename,content = edited_file(colour)
      files[filename] = content
    end
    files
  end

  # - - - - - - - - - - - - - - - - -

  def check_start_point_src_red_green_amber_using_runner_statefull
    banner
    if manifest['runner_choice'] == 'stateless'
      puts "manifest.json ==> 'runner_choice':'stateless'"
      puts 'checking anyway'
    end
    @runner = RunnerServiceStatefull.new
    in_kata {
      assert_timed_run_statefull(:red  , 'rhino')
      assert_timed_run_statefull(:amber, 'antelope')
      assert_timed_run_statefull(:green, 'gopher')
    }
  end

  def in_kata
    @runner.kata_new(image_name, kata_id)
    begin
      yield
    ensure
      @runner.kata_old(image_name, kata_id)
    end
  end

  def assert_timed_run_statefull(colour, avatar_name)
    # TODO : >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    # TODO: this needs to be run statefully. Viz on the same avatar
    # TODO : >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    as_avatar(avatar_name) {
      args = [image_name]
      args << kata_id
      args << avatar_name
      args << (deleted_filenames=[])
      args << changed_files(colour)
      args << (max_seconds=10)
      took,sss = timed { @runner.run(*args) }
      assert_rag(colour, sss, "dir == #{start_point_dir}")
      puts "#{colour}: OK (~#{took} seconds)"
    }
  end

  def as_avatar(avatar_name)
    @runner.avatar_new(image_name, kata_id, avatar_name, start_files)
    begin
      yield
    ensure
      @runner.avatar_old(image_name, kata_id, avatar_name)
    end
  end

  def changed_files(colour)
    if colour == :red
      {}
    else
      filename,content = edited_file(colour)
      { filename => content }
    end
  end

  # - - - - - - - - - - - - - - - - -

  def edited_file(colour)
    args = options[colour.to_s]
    if !args.nil?
      filename = args['filename']
      from = args['from']
      to = args['to']
    elsif colour == :amber
      from = '6 * 9'
      to = '6 * 9sdsd'
      filename = filename_6_times_9(from)
    elsif colour == :green
      from = '6 * 9'
      to = '6 * 7'
      filename = filename_6_times_9(from)
    end
    return filename, start_files[filename].sub(from,to)
  end

  # - - - - - - - - - - - - - - - - -

  def filename_6_times_9(from)
    filenames = start_files.select { |_,content| content.include? from }
    if filenames == []
      failed [ "no '#{from}' file found" ]
    end
    if filenames.length > 1
      failed [ "multiple '#{from}' files " + filenames.inspect ]
    end
    filenames.keys[0]
  end

  # - - - - - - - - - - - - - - - - -

  def options
    # TODO : >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    # TODO: add handling of failed json parse
    # TODO : >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    options_file = start_point_dir + '/options.json'
    if File.exists? options_file
      JSON.parse(IO.read(options_file))
    else
      {}
    end
  end

  # - - - - - - - - - - - - - - - - -

  def manifest
    manifest_file = start_point_dir + '/manifest.json'
    JSON.parse(IO.read(manifest_file))
  end

  # - - - - - - - - - - - - - - - - -

  def timed
    started = Time.now
    result = yield
    stopped = Time.now
    took = (stopped - started).round(2)
    return took,result
  end

  # - - - - - - - - - - - - - - - - -

  def assert_rag(expected_colour, sss, diagnostic)
    actual_colour = call_rag_lambda(sss)
    unless expected_colour == actual_colour
      failed [ diagnostic,
        "expected_colour == #{expected_colour}",
        "  actual_colour == #{actual_colour}",
        "stdout == #{sss['stdout']}",
        "stderr == #{sss['stderr']}",
        "status == #{sss['status']}"
      ]
    end
  end

  # - - - - - - - - - - - - - - - - -

  def call_rag_lambda(sss)
    # TODO : >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    # TODO: improve diagnostics if cat/eval/call fails
    # TODO : >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    cat_rag_filename = "docker run --rm -it #{image_name} cat #{rag_filename}"
    src = assert_backtick cat_rag_filename
    fn = eval(src)
    fn.call(sss['stdout'], sss['stderr'], sss['status'])
  end

  # - - - - - - - - - - - - - - - - -

  def start_files
    # start-point has already been verified
    manifest_filename = start_point_dir + '/manifest.json'
    manifest = IO.read(manifest_filename)
    manifest = JSON.parse(manifest)
    files = {}
    manifest['visible_filenames'].each do |filename|
      path = start_point_dir + '/' + filename
      files[filename] = IO.read(path)
    end
    files
  end

  # - - - - - - - - - - - - - - - - -

  def banner
    line = '-' * 42
    title = caller_locations(1,1)[0].label
    print_to STDOUT, '', line, title
  end

  # - - - - - - - - - - - - - - - - -

  def assert_system(command)
    system command
    status = $?.exitstatus
    unless status == success
      failed command, "exit_status == #{status}"
    end
  end

  def assert_backtick(command)
    output = `#{command}`
    status = $?.exitstatus
    unless status == success
      failed command, "exit_status == #{status}", output
    end
    output
  end

  # - - - - - - - - - - - - - - - - -

  def failed(*lines)
    print_to STDERR, 'FAILED', lines
    exit 1
  end

  def print_to(stream, *lines)
    lines.each { |line| stream.puts line }
  end

  # - - - - - - - - - - - - - - - - -

  def image_name
    @args[:image_name]
  end

  def test_framework?
    @args[:test_framework]
  end

  def start_point_dir
    src_dir + '/start_point'
  end

  def src_dir
    @src_dir
  end

  def success
    0
  end

  def rag_filename
    '/usr/local/bin/red_amber_green.rb'
  end

  def kata_id
    '6F4F4E4759'
  end

end