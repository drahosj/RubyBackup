require 'json'
require 'time'
require 'digest'
require 'find'

class DirectoryRoot
  attr_accessor :path
  attr_accessor :blacklist
  attr_accessor :whitelist
  def initialize path, black, white
    @path = path
    @blacklist = black
    @whitelist = white
  end
  def to_s
    if @blacklist != nil
      "'#{@path}' : !#{@blacklist}"
    elsif @whitelist != nil
      "'#{@path}' : =#{@whitelist}"
    else
      "'#{@path}"
    end
  end
end

class Server
  attr_reader :files
  attr_reader :directories
  attr_reader :datestamp
  attr_reader :all_directories
  attr_reader :links
  attr_reader :syncs
  def initialize
    @hostname = "localhost"
    @user = ""
    @root = "/"
    @metaroot = "/tmp/backup/"
    @files = []
    @directories = []
    @datestamp = Time.now.iso8601.sub(/T.*$/, "")
  end
  
  def metaroot x = nil
    @metaroot = x unless x == nil
    @metaroot
  end
  
  def hostname x = nil
    @hostname = x unless x == nil
    @hostname
  end
  
  def user x = nil
    @user = x unless x == nil
    @user
  end
  
  def root x = nil
    @root = x unless x == nil
    @root
  end
  
  def directory d, black, white
    @directories << DirectoryRoot.new(d, black, white)
  end
  
  def file f
    @files << f
  end
  
  def walk_directories
    @all_directories = []
    @directories.each do |d|
      Find.find(d.path) do |path|
        if FileTest.directory? path
          if d.blacklist and d.blacklist =~ File.basename(path)
            Find.prune 
          else
            @all_directories << path 
          end
        end
        if FileTest.file? path
          if d.blacklist
            @files << path unless d.blacklist =~ File.basename(path)
          elsif d.whitelist
            @files << path if d.whitelist =~ File.basename(path)
          else
            @files << path
          end
        end
      end
    end
  end
  
  def get_remote_hashes
    IO.popen("ssh #{@user}@#{@hostname} 'ruby'") do |p|
      p.puts $get_last_hashes
      p.puts @root
      JSON.parse(p.gets)
    end
  end
  
  def make_remote_directory_structure
    IO.popen("ssh #{@user}@#{@hostname} 'ruby'") do |p|
      p.puts @root
      p.puts @datestamp
      p.puts @directories.to_json
    end
  end
  
  def remote_link_copy
  end
  
  def rsync_new_files
  end
  
  def link_or_sync remote_hashes
    @links = []
    @syncs = []
    @files.each do |f|
      if remote_hashes[f] == @hash_table[f]
        @links << f
      else
        @syncs << f
      end
    end
  end
  
  def make_hash_table
    @hash_table = {}
    @files.each do |f|
      hash = Digest::SHA256.file f
      @hash_table[f] = hash.base64digest
    end
    IO.write("#{@metaroot}/#{@datestamp}/hashes.json", @hash_table.to_json)
  end
  
  def setup
    Dir.mkdir @metaroot unless FileTest.exists? @metaroot
    name = "#{@metaroot}/#{@datestamp}"
    Dir.mkdir name unless FileTest.exists? name
  end
end

class Configuration
  def initialize
    @servers = []
  end
  
  def add_server s
    @servers << s
  end
  
  def set
    @servers.last
  end
  
  def run
    s = @servers.first
    s.setup
    s.walk_directories
    s.make_hash_table
    remote_hashes = s.get_remote_hashes
    s.make_remote_directory_structure
    
    s.link_or_sync(remote_hashes)
    
    puts "links"
    print s.links
    puts "syncs"
    print s.syncs
  end
end

@config = Configuration.new

def run
  @config.run
end

def server
  s = Server.new
  @config.add_server s
  yield
end

def hostname name
  @config.set.hostname name
end

def user u
  @config.set.user u
end

def destroot r
  @config.set.root r
end

def metaroot r
  @config.set.metaroot r
end

def file f
  @config.set.file f
end

def directory d, blacklist: nil, whitelist: nil
  unless blacklist == nil or whitelist == nil
    raise ArgumentError, "Only either blacklist or whitelist may be specified"
  end
    
  @config.set.directory(d, blacklist, whitelist)
end

#Input order: bacup_root, datestamp, directories
$build_directory_structure = <<'END_REMOTE_SCRIPT'
require 'json'

def main
  backup_root = gets.chomp
  datestamp = gets.chomp
  directories = JSON.parse(gets.chomp)

  directories.each {|d| Dir.mkdir(backup_root + "/" + datestamp + "/" + d) }
end

main
END_REMOTE_SCRIPT

#Input order: backup_root
#Output order: hashes.json
$get_last_hashes = <<'END_REMOTE_SCRIPT'
require 'find'

def main

  backup_root = gets.chomp

  dirs = []

  Find.find (backup_root) do |path|
    Find.prune if FileTest.directory?
    dirs << File.basename(path)
  end
  puts IO.read("#{backup_root}/#{dirs.last}/.meta/hashes.json")
end

main
END_REMOTE_SCRIPT

#Input order: backup_root, syncs.json, links.json
$copy_and_link = <<'END_REMOTE_SCRIPT'
require 'find'

def main
  bacup_root = gets.chomp

  dirs = []

  Find.find (backup_root) do |path|
    Find.prune if FileTest.directory?
    dirs << File.basename(path)
  end

  old_root = dirs[-2]
  new_root = dirs[-1]

  syncs = JSON.parse(gets)
  links = JSON.parse(gets)

  f = File.open("#{backup_root}/#{new_root}/.meta/log")

  links.each do |l|
    r = system "ln #{backup_root}/#{old_root}/#{l} #{backup_root}/#{new_root}/#{l}"
    f.puts "Linking #{l} - Return status #{r}"
  end

  syncs.each do |s|
    r = system "cp #{backup_root}/#{old_root}/#{l} #{backup_root}/#{new_root}/#{l}"
    f.puts "Copying #{l} - Return status #{r}"
  end

  f.close
end

main
END_REMOTE_SCRIPT