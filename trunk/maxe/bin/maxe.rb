#!/usr/bin/ruby

require 'yaml'
require 'erb'

def read_properties(file_name)
  properties = {}
  File::readlines(file_name).each do | line |
    line.chomp!
    next if (line =~ /^\s*\#/ or line =~ /^\s*$/)

    pair = line.match(/^\s*(.+)\s*=\s*(.+)\s*$/)
    raise "unexpected line in '#{file_name}': #{line}" if (pair == nil)

    properties[pair[1]] = pair[2]
  end
  return properties
end


# read maxe.conf properties and load each property as a global constant
# prefixed with $MAXE_ and made uppercase, so install_dir becomes $MAXE_INSTALL_DIR
$MAXE_CONF = read_properties("/etc/maxe.conf")
$MAXE_CONF.each do | name, value |
  eval("$MAXE_#{name.upcase}=#{value.inspect}")
end

# assert key properties are present
raise "no 'install_dir' configured" if ($MAXE_INSTALL_DIR == nil)
raise "no 'machines_data' configured" if ($MAXE_MACHINES_DATA == nil)
raise "no 'scripts_dir' configured" if ($MAXE_SCRIPTS_DIR == nil)

# reset $MAXE_MACHINES_DATA to point to the load yaml file it points to
$MAXE_MACHINES_DATA = YAML::load(File::readlines($MAXE_MACHINES_DATA).join())

# load all supporting maxe libraries
Dir["#{$MAXE_INSTALL_DIR}/lib/*.rb"].each do | lib_script |
  load(lib_script)
end

# set constant list of supported phases
$MAXE_PHASE_NAMES = ['setup', 'install', 'config', 'restart']

# determine script name (symlink to this file)
$MAXE_SCRIPT = File::basename($0)

# determine requested phase from script name
$MAXE_PHASES = [$0.match(/^(.+\/)?.+_(.+)(\..+)?/)[2]]
raise "could not determine phase" if ($MAXE_PHASES.length <= 0)

# determine current machine name from local host name
$MAXE_MACHINE = ENV['HOSTNAME'].match(/^(.+?)(\.|$)/)[1]
raise "machine name not know" if ($MAXE_MACHINE == nil)

# pull machine conf from the machine database
$MAXE_MACHINE_CONF = $MAXE_MACHINES_DATA[$MAXE_MACHINE]
raise "no configuration for machine '#{$MAXE_MACHINE}'" if ($MAXE_MACHINE_CONF == nil)

# determine machine needs
$MAXE_MACHINE_NEEDS = $MAXE_MACHINE_CONF['needs']
raise "no needs for machine '#{$MAXE_MACHINE}'" if ($MAXE_MACHINE_NEEDS == nil)

# determine machine archetype
$MAXE_MACHINE_ARCHETYPE = $MAXE_MACHINE_CONF['archetype']
raise "no archetype for machine '#{$MAXE_MACHINE}'" if ($MAXE_MACHINE_ARCHETYPE == nil)

# determine var space
$MAXE_VAR = $MAXE_MACHINE_CONF['var']
raise "no var for machine '#{$MAXE_MACHINE}'" if ($MAXE_VAR == nil)

# default target machine is the current machine
#$MAXE_TARGET_MACHINE = $MAXE_MACHINE



# parse command-line arguments
while(arg = ARGV.shift)
  case arg
  when "--prompt"
    $MAXE_PROMPT = true
  when "--show-work"
    $MAXE_SHOW_WORK = true
  when "--debug"
    $MAXE_DEBUG = true
    $MAXE_PROMPT = true
    $MAXE_SHOW_WORK = true
  when "--synopsis"
    $MAXE_SYNOPSIS = true
  when "--target-tasks"
    $MAXE_TARGET_TASKS = ARGV.shift.split(",")
  when "--all-phases"
    $MAXE_PHASES = $MAXE_PHASE_NAMES
  when "--all-provides"
    $MAXE_ALL_PROVIDES = true
#  when "--target-machine"
#    $MAXE_TARGET_MACHINE = ARGV.shift
#  when /^@/
#    $MAXE_TARGET_MACHINE = arg[1..-1]
  when "--help", "/?", "-?", "/help", "-help", "-h"
    system("man #{$MAXE_SCRIPT}")
    exit 0
  else
    raise "unexpected parameter '#{arg}'"
  end
end



# load every maxe script; will be filtered by archetype and phase(s)
tasks = Maxe::Tasks.new
Dir["#{$MAXE_SCRIPTS_DIR}/*"].each do | script_file |
  tasks.load_script(File::basename(script_file))
end

# execute every qualifying script
tasks.execute