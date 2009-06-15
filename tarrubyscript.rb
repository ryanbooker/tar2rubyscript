# License of this script, not of the application it contains:
#
# Copyright Erik Veenstra <tar2rubyscript@erikveen.dds.nl>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
# 
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place, Suite 330,
# Boston, MA 02111-1307 USA.

# Parts of this code are based on code from Thomas Hurst
# <tom@hur.st>.

# Tar2RubyScript constants

unless defined?(BLOCKSIZE)
  ShowContent	= ARGV.include?("--tar2rubyscript-list")
  JustExtract	= ARGV.include?("--tar2rubyscript-justextract")
  ToTar		= ARGV.include?("--tar2rubyscript-totar")
  Preserve	= ARGV.include?("--tar2rubyscript-preserve")
end

ARGV.concat	[]

ARGV.delete_if{|arg| arg =~ /^--tar2rubyscript-/}

ARGV << "--tar2rubyscript-preserve"	if Preserve

# Tar constants

unless defined?(BLOCKSIZE)
  BLOCKSIZE		= 512

  NAMELEN		= 100
  MODELEN		= 8
  UIDLEN		= 8
  GIDLEN		= 8
  CHKSUMLEN		= 8
  SIZELEN		= 12
  MAGICLEN		= 8
  MODTIMELEN		= 12
  UNAMELEN		= 32
  GNAMELEN		= 32
  DEVLEN		= 8

  TMAGIC		= "ustar"
  GNU_TMAGIC		= "ustar  "
  SOLARIS_TMAGIC	= "ustar\00000"

  MAGICS		= [TMAGIC, GNU_TMAGIC, SOLARIS_TMAGIC]

  LF_OLDFILE		= '\0'
  LF_FILE		= '0'
  LF_LINK		= '1'
  LF_SYMLINK		= '2'
  LF_CHAR		= '3'
  LF_BLOCK		= '4'
  LF_DIR		= '5'
  LF_FIFO		= '6'
  LF_CONTIG		= '7'

  GNUTYPE_DUMPDIR	= 'D'
  GNUTYPE_LONGLINK	= 'K'	# Identifies the *next* file on the tape as having a long linkname.
  GNUTYPE_LONGNAME	= 'L'	# Identifies the *next* file on the tape as having a long name.
  GNUTYPE_MULTIVOL	= 'M'	# This is the continuation of a file that began on another volume.
  GNUTYPE_NAMES		= 'N'	# For storing filenames that do not fit into the main header.
  GNUTYPE_SPARSE	= 'S'	# This is for sparse files.
  GNUTYPE_VOLHDR	= 'V'	# This file is a tape/volume header.  Ignore it on extraction.
end

class Dir
  def self.rm_rf(entry)
    begin
      File.chmod(0755, entry)
    rescue
    end

    if File.ftype(entry) == "directory"
      pdir	= Dir.pwd

      Dir.chdir(entry)
        Dir.open(".") do |d|
          d.each do |e|
            Dir.rm_rf(e)	if not [".", ".."].include?(e)
          end
        end
      Dir.chdir(pdir)

      begin
        Dir.delete(entry)
      rescue => e
        $stderr.puts e.message
      end
    else
      begin
        File.delete(entry)
      rescue => e
        $stderr.puts e.message
      end
    end
  end
end

class Reader
  def initialize(filehandle)
    @fp	= filehandle
  end

  def extract
    each do |entry|
      entry.extract
    end
  end

  def list
    each do |entry|
      entry.list
    end
  end

  def each
    @fp.rewind

    while entry	= next_entry
      yield(entry)
    end
  end

  def next_entry
    buf	= @fp.read(BLOCKSIZE)

    if buf.length < BLOCKSIZE or buf == "\000" * BLOCKSIZE
      entry	= nil
    else
      entry	= Entry.new(buf, @fp)
    end

    entry
  end
end

class Entry
  attr_reader(:header, :data)

  def initialize(header, fp)
    @header	= Header.new(header)

    readdata =
    lambda do |header|
      padding	= (BLOCKSIZE - (header.size % BLOCKSIZE)) % BLOCKSIZE
      @data	= fp.read(header.size)	if header.size > 0
      dummy	= fp.read(padding)	if padding > 0
    end

    readdata.call(@header)

    if @header.longname?
      gnuname		= @data[0..-2]

      header		= fp.read(BLOCKSIZE)
      @header		= Header.new(header)
      @header.name	= gnuname

      readdata.call(@header)
    end
  end

  def extract
    if not @header.name.empty?
      if @header.symlink?
        begin
          File.symlink(@header.linkname, @header.name)
        rescue SystemCallError => e
          $stderr.puts "Couldn't create symlink #{@header.name}: " + e.message
        end
      elsif @header.link?
        begin
          File.link(@header.linkname, @header.name)
        rescue SystemCallError => e
          $stderr.puts "Couldn't create link #{@header.name}: " + e.message
        end
      elsif @header.dir?
        begin
          Dir.mkdir(@header.name, @header.mode)
        rescue SystemCallError => e
          $stderr.puts "Couldn't create dir #{@header.name}: " + e.message
        end
      elsif @header.file?
        begin
          File.open(@header.name, "wb") do |fp|
            fp.write(@data)
            fp.chmod(@header.mode)
          end
        rescue => e
          $stderr.puts "Couldn't create file #{@header.name}: " + e.message
        end
      else
        $stderr.puts "Couldn't handle entry #{@header.name} (flag=#{@header.linkflag.inspect})."
      end

      #File.chown(@header.uid, @header.gid, @header.name)
      #File.utime(Time.now, @header.mtime, @header.name)
    end
  end

  def list
    if not @header.name.empty?
      if @header.symlink?
        $stderr.puts "s %s -> %s" % [@header.name, @header.linkname]
      elsif @header.link?
        $stderr.puts "l %s -> %s" % [@header.name, @header.linkname]
      elsif @header.dir?
        $stderr.puts "d %s" % [@header.name]
      elsif @header.file?
        $stderr.puts "f %s (%s)" % [@header.name, @header.size]
      else
        $stderr.puts "Couldn't handle entry #{@header.name} (flag=#{@header.linkflag.inspect})."
      end
    end
  end
end

class Header
  attr_reader(:name, :uid, :gid, :size, :mtime, :uname, :gname, :mode, :linkflag, :linkname)
  attr_writer(:name)

  def initialize(header)
    fields	= header.unpack('A100 A8 A8 A8 A12 A12 A8 A1 A100 A8 A32 A32 A8 A8')
    types	= ['str', 'oct', 'oct', 'oct', 'oct', 'time', 'oct', 'str', 'str', 'str', 'str', 'str', 'oct', 'oct']

    begin
      converted	= []
      while field = fields.shift
        type	= types.shift

        case type
        when 'str'	then converted.push(field)
        when 'oct'	then converted.push(field.oct)
        when 'time'	then converted.push(Time::at(field.oct))
        end
      end

      @name, @mode, @uid, @gid, @size, @mtime, @chksum, @linkflag, @linkname, @magic, @uname, @gname, @devmajor, @devminor	= converted

      @name.gsub!(/^\.\//, "")
      @linkname.gsub!(/^\.\//, "")

      @raw	= header
    rescue ArgumentError => e
      raise "Couldn't determine a real value for a field (#{field})"
    end

    raise "Magic header value #{@magic.inspect} is invalid."	if not MAGICS.include?(@magic)

    @linkflag	= LF_FILE			if @linkflag == LF_OLDFILE or @linkflag == LF_CONTIG
    @linkflag	= LF_DIR			if @linkflag == LF_FILE and @name[-1] == '/'
    @size	= 0				if @size < 0
  end

  def file?
    @linkflag == LF_FILE
  end

  def dir?
    @linkflag == LF_DIR
  end

  def symlink?
    @linkflag == LF_SYMLINK
  end

  def link?
    @linkflag == LF_LINK
  end

  def longname?
    @linkflag == GNUTYPE_LONGNAME
  end
end

class Content
  @@count	= 0	unless defined?(@@count)

  def initialize
    @@count += 1

    @archive	= File.open(File.expand_path(__FILE__), "rb"){|f| f.read}.gsub(/\r/, "").split(/\n\n/)[-1].split("\n").collect{|s| s[2..-1]}.join("\n").unpack("m").shift
    temp	= ENV["TEMP"]
    temp	= "/tmp"	if temp.nil?
    temp	= File.expand_path(temp)
    @tempfile	= "#{temp}/tar2rubyscript.f.#{Process.pid}.#{@@count}"
  end

  def list
    begin
      File.open(@tempfile, "wb")	{|f| f.write @archive}
      File.open(@tempfile, "rb")	{|f| Reader.new(f).list}
    ensure
      File.delete(@tempfile)
    end

    self
  end

  def cleanup
    @archive	= nil

    self
  end
end

class TempSpace
  @@count	= 0	unless defined?(@@count)

  def initialize
    @@count += 1

    @archive	= File.open(File.expand_path(__FILE__), "rb"){|f| f.read}.gsub(/\r/, "").split(/\n\n/)[-1].split("\n").collect{|s| s[2..-1]}.join("\n").unpack("m").shift
    @olddir	= Dir.pwd
    temp	= ENV["TEMP"]
    temp	= "/tmp"	if temp.nil?
    temp	= File.expand_path(temp)
    @tempfile	= "#{temp}/tar2rubyscript.f.#{Process.pid}.#{@@count}"
    @tempdir	= "#{temp}/tar2rubyscript.d.#{Process.pid}.#{@@count}"

    @@tempspace	= self

    @newdir	= @tempdir

    @touchthread =
    Thread.new do
      loop do
        sleep 60*60

        touch(@tempdir)
        touch(@tempfile)
      end
    end
  end

  def extract
    Dir.rm_rf(@tempdir)	if File.exists?(@tempdir)
    Dir.mkdir(@tempdir)

    newlocation do

		# Create the temp environment.

      File.open(@tempfile, "wb")	{|f| f.write @archive}
      File.open(@tempfile, "rb")	{|f| Reader.new(f).extract}

		# Eventually look for a subdirectory.

      entries	= Dir.entries(".")
      entries.delete(".")
      entries.delete("..")

      if entries.length == 1
        entry	= entries.shift.dup
        if File.directory?(entry)
          @newdir	= "#{@tempdir}/#{entry}"
        end
      end
    end

		# Remember all File objects.

    @ioobjects	= []
    ObjectSpace::each_object(File) do |obj|
      @ioobjects << obj
    end

    at_exit do
      @touchthread.kill

		# Close all File objects, opened in init.rb .

      ObjectSpace::each_object(File) do |obj|
        obj.close	if (not obj.closed? and not @ioobjects.include?(obj))
      end

		# Remove the temp environment.

      Dir.chdir(@olddir)

      Dir.rm_rf(@tempfile)
      Dir.rm_rf(@tempdir)
    end

    self
  end

  def cleanup
    @archive	= nil

    self
  end

  def touch(entry)
    entry	= entry.gsub!(/[\/\\]*$/, "")	unless entry.nil?

    return	unless File.exists?(entry)

    if File.directory?(entry)
      pdir	= Dir.pwd

      begin
        Dir.chdir(entry)

        begin
          Dir.open(".") do |d|
            d.each do |e|
              touch(e)	unless [".", ".."].include?(e)
            end
          end
        ensure
          Dir.chdir(pdir)
        end
      rescue Errno::EACCES => error
        $stderr.puts error
      end
    else
      File.utime(Time.now, File.mtime(entry), entry)
    end
  end

  def oldlocation(file="")
    if block_given?
      pdir	= Dir.pwd

      Dir.chdir(@olddir)
        res	= yield
      Dir.chdir(pdir)
    else
      res	= File.expand_path(file, @olddir)	if not file.nil?
    end

    res
  end

  def newlocation(file="")
    if block_given?
      pdir	= Dir.pwd

      Dir.chdir(@newdir)
        res	= yield
      Dir.chdir(pdir)
    else
      res	= File.expand_path(file, @newdir)	if not file.nil?
    end

    res
  end

  def templocation(file="")
    if block_given?
      pdir	= Dir.pwd

      Dir.chdir(@tempdir)
        res	= yield
      Dir.chdir(pdir)
    else
      res	= File.expand_path(file, @tempdir)	if not file.nil?
    end

    res
  end

  def self.oldlocation(file="")
    if block_given?
      @@tempspace.oldlocation { yield }
    else
      @@tempspace.oldlocation(file)
    end
  end

  def self.newlocation(file="")
    if block_given?
      @@tempspace.newlocation { yield }
    else
      @@tempspace.newlocation(file)
    end
  end

  def self.templocation(file="")
    if block_given?
      @@tempspace.templocation { yield }
    else
      @@tempspace.templocation(file)
    end
  end
end

class Extract
  @@count	= 0	unless defined?(@@count)

  def initialize
    @archive	= File.open(File.expand_path(__FILE__), "rb"){|f| f.read}.gsub(/\r/, "").split(/\n\n/)[-1].split("\n").collect{|s| s[2..-1]}.join("\n").unpack("m").shift
    temp	= ENV["TEMP"]
    temp	= "/tmp"	if temp.nil?
    @tempfile	= "#{temp}/tar2rubyscript.f.#{Process.pid}.#{@@count += 1}"
  end

  def extract
    begin
      File.open(@tempfile, "wb")	{|f| f.write @archive}
      File.open(@tempfile, "rb")	{|f| Reader.new(f).extract}
    ensure
      File.delete(@tempfile)
    end

    self
  end

  def cleanup
    @archive	= nil

    self
  end
end

class MakeTar
  def initialize
    @archive	= File.open(File.expand_path(__FILE__), "rb"){|f| f.read}.gsub(/\r/, "").split(/\n\n/)[-1].split("\n").collect{|s| s[2..-1]}.join("\n").unpack("m").shift
    @tarfile	= File.expand_path(__FILE__).gsub(/\.rbw?$/, "") + ".tar"
  end

  def extract
    File.open(@tarfile, "wb")	{|f| f.write @archive}

    self
  end

  def cleanup
    @archive	= nil

    self
  end
end

def oldlocation(file="")
  if block_given?
    TempSpace.oldlocation { yield }
  else
    TempSpace.oldlocation(file)
  end
end

def newlocation(file="")
  if block_given?
    TempSpace.newlocation { yield }
  else
    TempSpace.newlocation(file)
  end
end

def templocation(file="")
  if block_given?
    TempSpace.templocation { yield }
  else
    TempSpace.templocation(file)
  end
end

if ShowContent
  Content.new.list.cleanup
elsif JustExtract
  Extract.new.extract.cleanup
elsif ToTar
  MakeTar.new.extract.cleanup
else
  TempSpace.new.extract.cleanup

  $:.unshift(templocation)
  $:.unshift(newlocation)
  $:.push(oldlocation)

  verbose	= $VERBOSE
  $VERBOSE	= nil
  s	= ENV["PATH"].dup
  if Dir.pwd[1..2] == ":/"	# Hack ???
    s << ";#{templocation.gsub(/\//, "\\")}"
    s << ";#{newlocation.gsub(/\//, "\\")}"
    s << ";#{oldlocation.gsub(/\//, "\\")}"
  else
    s << ":#{templocation}"
    s << ":#{newlocation}"
    s << ":#{oldlocation}"
  end
  ENV["PATH"]	= s
  $VERBOSE	= verbose

  TAR2RUBYSCRIPT	= true	unless defined?(TAR2RUBYSCRIPT)

  newlocation do
    if __FILE__ == $0
      $_0 = File.expand_path("./init.rb")
      alias $__0 $0
      alias $0 $_0

      if File.file?("./init.rb")
        load File.expand_path("./init.rb")
      else
        $stderr.puts "%s doesn't contain an init.rb ." % __FILE__
      end
    else
      if File.file?("./init.rb")
        load File.expand_path("./init.rb")
      end
    end
  end
end
