$: << File.dirname(File.expand_path(__FILE__))

require "ev/oldandnewlocation"
require "ev/ftools"
require "rbconfig"

exit	if ARGV.include?("--tar2rubyscript-exit")

def backslashes(s)
  s	= s.gsub(/^\.\//, "").gsub(/\//, "\\\\")	if windows?
  s
end

def linux?
  not windows? and not cygwin?			# Hack ???
end

def windows?
  not (target_os.downcase =~ /32/).nil?		# Hack ???
end

def cygwin?
  not (target_os.downcase =~ /cyg/).nil?	# Hack ???
end

def target_os
  Config::CONFIG["target_os"] or ""
end

PRESERVE	= ARGV.include?("--tar2rubyscript-preserve")

ARGV.delete_if{|arg| arg =~ /^--tar2rubyscript-/}

scriptfile	= newlocation("tarrubyscript.rb")
tarfile		= oldlocation(ARGV.shift)
rbfile		= oldlocation(ARGV.shift)
licensefile	= oldlocation(ARGV.shift)

if tarfile.nil?
  usagescript	= "init.rb"
  usagescript	= "tar2rubyscript.rb"	if defined?(TAR2RUBYSCRIPT)

  $stderr.puts <<-EOF

	Usage: ruby #{usagescript} application.tar [application.rb [licence.txt]]
	       or
	       ruby #{usagescript} application[/] [application.rb [licence.txt]]
	
	If \"application.rb\" is not provided or equals to \"-\", it will
	be derived from \"application.tar\" or \"application/\".
	
	If a license is provided, it will be put at the beginning of
	The Application.
	
	For more information, see
	http://www.erikveen.dds.nl/tar2rubyscript/index.html .
	EOF

  exit 1
end

TARMODE	= File.file?(tarfile)
DIRMODE	= File.directory?(tarfile)

if not File.exist?(tarfile)
  $stderr.puts "#{tarfile} doesn't exist."
  exit
end

if not licensefile.nil? and not licensefile.empty? and not File.file?(licensefile)
  $stderr.puts "#{licensefile} doesn't exist."
  exit
end

script	= File.open(scriptfile){|f| f.read}

pdir	= Dir.pwd

tmpdir	= tmplocation(File.basename(tarfile))

File.mkpath(tmpdir)

Dir.chdir(tmpdir)

  if TARMODE and not PRESERVE
    begin
      tar	= "tar"
      system(backslashes("#{tar} xf #{tarfile}"))
    rescue
      tar	= backslashes(newlocation("tar.exe"))
      system(backslashes("#{tar} xf #{tarfile}"))
    end
  end

  if DIRMODE
    dir		= File.dirname(tarfile)
    file	= File.basename(tarfile)
    begin
      tar	= "tar"
      system(backslashes("#{tar} c -C #{dir} #{file} | #{tar} x"))
    rescue
      tar	= backslashes(newlocation("tar.exe"))
      system(backslashes("#{tar} c -C #{dir} #{file} | #{tar} x"))
    end
  end

  entries	= Dir.entries(".")
  entries.delete(".")
  entries.delete("..")

  if entries.length == 1
    entry	= entries.shift.dup
    if File.directory?(entry)
      Dir.chdir(entry)
    end
  end

  if File.file?("tar2rubyscript.bat") and windows?
    $stderr.puts "Running tar2rubyscript.bat ..."

    system(".\\tar2rubyscript.bat")
  end

  if File.file?("tar2rubyscript.sh") and (linux? or cygwin?)
    $stderr.puts "Running tar2rubyscript.sh ..."

    system("sh -c \". ./tar2rubyscript.sh\"")
  end

Dir.chdir("..")

  $stderr.puts "Creating archive..."

  if TARMODE and PRESERVE
    archive	= File.open(tarfile, "rb"){|f| [f.read].pack("m").split("\n").collect{|s| "# " + s}.join("\n")}
  else
    what	= "*"
    what	= "*.*"	if windows?
    tar		= "tar"
    tar		= backslashes(newlocation("tar.exe"))	if windows?
    archive	= IO.popen("#{tar} c #{what}", "rb"){|f| [f.read].pack("m").split("\n").collect{|s| "# " + s}.join("\n")}
  end

Dir.chdir(pdir)

if not licensefile.nil? and not licensefile.empty?
  $stderr.puts "Adding license..."

  lic	= File.open(licensefile){|f| f.readlines}

  lic.collect! do |line|
    line.gsub!(/[\r\n]/, "")
    line	= "# #{line}"	unless line =~ /^[ \t]*#/
    line
  end

  script	= "# License, not of this script, but of the application it contains:\n#\n" + lic.join("\n") + "\n\n" + script
end

rbfile	= tarfile.gsub(/\.tar$/, "") + ".rb"	if (rbfile.nil? or File.basename(rbfile) == "-")

$stderr.puts "Creating #{File.basename(rbfile)} ..."

File.open(rbfile, "wb") do |f|
  f.write script
  f.write "\n"
  f.write "\n"
  f.write archive
  f.write "\n"
end
