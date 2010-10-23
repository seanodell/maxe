require 'yaml'

require "maxe/script.rb"
require "maxe/diff.rb"

$MAXE_PHASE_NAMES = ['upload', 'setup', 'install', 'config', 'restart']

$MAXE_PHASES = [$0.match(/^(.+\/)?.+_(.+)(\..+)?/)[2]]
raise "could not determine phase" if ($MAXE_PHASES.length <= 0)


$MAXE_CONF = YAML::load(File::readlines("/etc/maxe/maxe.yaml").join("\n"))


$MAXE_SCRIPT = File::basename($0)

$MAXE_MACHINE = ENV['HOSTNAME'].match(/^(.+?)(\.|$)/)[1]
raise "machine name not know" if ($MAXE_MACHINE == nil)

$MAXE_TARGET_MACHINE = $MAXE_MACHINE

$MAXE_MACHINE_CONF = $MAXE_CONF['machines'][$MAXE_MACHINE]
raise "no configuration for machine '#{$MAXE_MACHINE}'" if ($MAXE_MACHINE_CONF == nil)

$MAXE_MACHINE_ARCHETYPE = $MAXE_MACHINE_CONF['archetype']
raise "no archetype for machine '#{$MAXE_MACHINE}'" if ($MAXE_MACHINE_ARCHETYPE == nil)

while(arg = ARGV.shift)
  case arg
  when "--debug"
    $MAXE_DEBUG = true
    $MAXE_PROMPT = true
    $MAXE_SHOW_DIFFS = true
  when "--prompt"
    $MAXE_PROMPT = true
  when "--show-diffs"
    $MAXE_SHOW_DIFFS = true
  when "--list-tasks"
    $MAXE_LIST_TASKS = true
  when "--all-phases"
    $MAXE_PHASES = $MAXE_PHASE_NAMES
  when "--synopsis"
    $MAXE_SYNOPSIS = true
  when "--target-tasks"
    $MAXE_TARGET_TASKS = ARGV.shift.split(",")
  when "--target-machine"
    $MAXE_TARGET_MACHINE = ARGV.shift
  when "--remote-machine"
    $MAXE_REMOTE_MACHINE = ARGV.shift
  when /^@/
    $MAXE_TARGET_MACHINE = arg[1..-1]
  when "--help", "/?", "-?", "/help", "-help", "-h"
    system("man #{$MAXE_SCRIPT}")
    exit 0
  else
    raise "unexpected parameter '#{arg}'"
  end
end



tasks = Maxe::Tasks.new
Dir["/etc/maxe/scripts/*"].each do | script_file |
  tasks.load_script(File::basename(script_file))
end
tasks.execute