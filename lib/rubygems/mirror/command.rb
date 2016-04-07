require 'rubygems/mirror'
require 'rubygems/command'
require 'yaml'

class Gem::Commands::MirrorCommand < Gem::Command
  SUPPORTS_INFO_SIGNAL = Signal.list['INFO']

  def initialize
    super 'mirror', 'Mirror a gem repository'
  end

  def description # :nodoc:
    <<-EOF
The mirror command uses the ~/.gem/.mirrorrc config file to mirror
remote gem repositories to a local path. The config file is a YAML
document that looks like this:

  ---
  - from: http://gems.example.com # source repository URI
    to: /path/to/mirror           # destination directory
    parallelism: 10               # use 10 threads for downloads
    retries: 3                    # retry 3 times if fail to download a gem, optional, def is 1. (no retry)
    delete: false                 # whether delete gems (if remote ones are removed),optional, default is false.
    skiperror: true               # whether skip error, optional, def is true. will stop at error if set this to false.
    maxage: 100                   # Maximum age of gems to fetch
    minversions: 20               # Ensure we fetch at least x amount of versions
    verbose: false                # True will display progress output

Multiple sources and destinations may be specified.
    EOF
  end

  def execute
    if pth = ENV['GEM_MIRROR_CONFIG']
      config_file = File.expand_path(pth)
    else
      config_file = File.join Gem.user_home, '.gem', '.mirrorrc'
    end

    raise "Config file #{config_file} not found" unless File.exist? config_file

    mirrors = YAML.load_file config_file

    raise "Invalid config file #{config_file}" unless mirrors.respond_to? :each

    mirrors.each do |mir|
      raise "mirror missing 'from' field" unless mir.has_key? 'from'
      raise "mirror missing 'to' field" unless mir.has_key? 'to'

      Gem.configuration.verbose = mir['verbose']

      get_from = mir['from']
      save_to = File.expand_path mir['to']
      parallelism = mir['parallelism']
      retries = mir['retries'] || 1
      skiperror = mir['skiperror']
      delete = mir['delete']
      maxage = mir['maxage'] || 1000000
      minversions = mir['minversions'] || 10000000

      raise "Directory not found: #{save_to}" unless File.exist? save_to
      raise "Not a directory: #{save_to}" unless File.directory? save_to

      mirror = Gem::Mirror.new(from: get_from, to: save_to, parallelism: parallelism, retries: retries, skiperror: skiperror, maxage: maxage, minversions: minversions)

      Gem::Mirror::SPECS_FILES.each do |sf|
        say "Fetching: #{mirror.from(sf)}"
      end

      #mirror.update_specs

      say "Total gems: #{mirror.gems.size} on rubygems"

      # Fetch all the specs
      num_to_fetch = mirror.gemspecs_to_fetch.size

      progress = ui.progress_reporter num_to_fetch,
                                  "Fetching #{num_to_fetch} gemspecs"

      trap(:INFO) { puts "Fetched: #{progress.count}/#{num_to_fetch}" } if SUPPORTS_INFO_SIGNAL

      mirror.update_gemspecs { progress.updated true }

      # Fetch the candidate gems
      num_to_fetch = mirror.gems_to_fetch.size

      progress = ui.progress_reporter num_to_fetch,
                                  "Fetching #{num_to_fetch} gems"

      trap(:INFO) { puts "Fetched: #{progress.count}/#{num_to_fetch}" } if SUPPORTS_INFO_SIGNAL

      mirror.update_gems { progress.updated true }


      if delete
        num_to_delete = mirror.gems_to_delete.size

        progress = ui.progress_reporter num_to_delete,
                                 "Deleting #{num_to_delete} gems"

        trap(:INFO) { puts "Fetched: #{progress.count}/#{num_to_delete}" } if SUPPORTS_INFO_SIGNAL

        mirror.delete_gems { progress.updated true }
      end
    end
  end
end
