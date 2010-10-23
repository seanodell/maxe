module Maxe

  class ArrayShifter
    attr_reader :line_no

    def initialize(array)
      @array = array
      @line_no = 0
    end

    def shift
      line = @array.shift
      @line_no = @line_no + 1
      return line
    end
  end



  Task = Struct.new("Task", :script_name, :phase, :order, :command, :id, :depend, :desc, :header, :section)



  class Tasks
    def initialize
      @tasks = []
    end



    def load_script(script_name)
      phase = script_name.match(/^.+_(.+)\..+/)[1]
      machine = script_name.match(/^(.+?)_.+\..+/)[1]
      machine = nil if (machine == 'common')

      return if ($MAXE_PHASES.index(phase) == nil)
      return if (machine != nil and machine.index($MAXE_MACHINE) == nil)

      script = File::readlines("#{$MAXE_ROOT}/scripts/#{script_name}").collect do | line |
        line.chomp
      end

      array = ArrayShifter.new(script)

      order = 0

      begin
        while(line = array.shift) do
          if (line =~ /.+!\s*$/)
            command = line.strip[0..-2]
            header = {}
            boundary = nil

            # build header
            while (line = array.shift)
              break if (line =~ /^\s*#{boundary}\s*$/)

              raise "'#{line}' unexpected" if (not line =~ /^[A-Z]+:/)

              pair = line.match(/^([A-Z]+):(.+)/)[1..2]

              name = pair[0].strip
              value = pair[1].strip

              boundary = value if(name == "BOUND")

              if (header[name] == nil)
                header[name] = [value]
              else
                header[name] << value
              end
            end

            raise "missing ID:" if (header['ID'] == nil)
            id = header['ID'][-1]

            archetypes = header['ARCHETYPE']
            desc = header['DESCRIPTION']
            depend = header['DEPEND']

            # build section lines
            section = []

            if (boundary)
              catch(:found) do
                while (line = array.shift)
                  break if (line =~ /^\s*#{boundary}\s*$/)
                  section << line
                end

                raise "END: value '#{boundary}' not found" if (not line =~ /^\s*#{boundary}\s*$/)
              end
            end

            next if ($MAXE_TARGET_TASKS != nil and $MAXE_TARGET_TASKS.index(id) == nil)
            next if (archetypes != nil and archetypes.index($MAXE_MACHINE_ARCHETYPE) == nil)

            section = section.collect do | line |
              next line.gsub(/\#\{\$MAXE_[_A-Z]+[^\{\}]*?\}/) do | substring |
                substring = substring[2..-2]
                begin
                  next eval(substring)
                rescue Exception => e
                  e.message << " evaluating '#{substring}'"
                  raise e
                end
              end
            end

            @tasks << Task.new(script_name, phase, order, command, id, depend, desc, header, section)
            order = order + 1
          elsif (not line =~/^\s*$/)
            raise "'#{line}' unexpected"
          end
        end
      rescue Exception => e
        e.message << " at line #{array.line_no} in '#{script_name}'"
        raise e
      end
    end



    def sort_tasks
      phase_order = ['upload', 'setup', 'install', 'config', 'restart']

      # first get a good starting order
      ordered_tasks = @tasks.sort do | l, r |
        lo = phase_order.index(l.phase)
        ro = phase_order.index(r.phase)
        next lo <=> ro if (lo != ro)
        lo = l.script_name
        ro = r.script_name
        next lo <=> ro if (lo != ro)
        next l.order <=> r.order
      end

      # build a reverse depend map to help clear up dependencies as tasks are resolved
      reverse_depend_map = {}
      ordered_tasks.each do | task |
        next if (task.depend == nil or task.depend.length <= 0)
        task.depend.each do | depend |
          reverse_depend = reverse_depend_map[depend]
          reverse_depend = reverse_depend_map[depend] = [] if (reverse_depend == nil)
          reverse_depend << task
        end
      end

      tasks = []

      # keep trying so long as there are tasks left to add to the final list
      while (ordered_tasks.length > 0)
        catch(:resolved_dependencies) do
          ordered_tasks.each_index do | index |
            task = ordered_tasks[index]

            # when a task has no more dependencies, it is ready to be added
            if (task.depend == nil or task.depend.length <= 0)
              tasks << task
              ordered_tasks[index] = nil

              reverse_depend = reverse_depend_map[task.id]
              if (reverse_depend != nil) # if other tasks depended on this (reverse lookup)
                reverse_depend.each do | depend_task |
                  depend_task.depend.delete(task.id) # then delete those dependencies
                end
                throw :resolved_dependencies # also throw to the outer loop again
              end
            end
          end
          # should only get here when the last run resolved no more dependencies.
          # if any tasks remain, that means they still had dependencies.
          # since no more dependencies can be resolved, these tasks are un-resolvable
          
          ordered_tasks.compact!
          if (ordered_tasks.length > 0) # at least one task was left (must have dependencies)
            raise "could not resolve dependencies (#{ordered_tasks[0].depend.join(', ')}) in #{ordered_tasks[0].id}"
          end
        end # end of catch

        ordered_tasks.compact!
      end # end of while loop

      @tasks = tasks
    end



    def print_synopsis

      col_width = @tasks.collect{|t|t.id}.max{|a,b|a.length<=>b.length}.length

      last_phase = nil
      last_script_name = nil
      @tasks.each do | task |
        if (last_phase != task.phase)
          last_phase = task.phase
          last_script_name = nil
          print("#{last_phase}\n")
        end
        if (last_script_name != task.script_name)
          last_script_name = task.script_name
          print("  #{last_script_name}\n")
        end
        printf("    %-*s %6s - %s\n", col_width, task.id, "(#{task.command})", task.desc)
      end
    end

    def print_diff(org_array, final_array)
      diff = Diff::LCS.diff(org_array, final_array)
      last_position = nil
      if (diff.length > 0)
        diff.each do | change_area |
          change_area.each do | change |
            if (last_position != (change.position - 1))
              position = change.position - 1
              printf("= %3s %s\n", position + 1, final_array[position]) if (position >= 0 and position < final_array.length)
            end
            last_position = change.position
            printf("%s %3s %s\n", change.action, change.position + 1, change.element)
          end
        end
        if (last_position != nil)
          position = last_position + 1
          printf("= %3s %s\n", position + 1, final_array[position]) if (position >= 0 and position < final_array.length)
        end
      else
        print "# NO CHANGE\n"
      end
    end



    def execute
      sort_tasks

      if ($MAXE_SYNOPSIS)
        print_synopsis
        exit 0
      end

      @tasks.each do | task |
        print "Processing (#{task.phase}) #{task.command} '#{task.id}' in '#{task.script_name}'\n"

        next if ($MAXE_LIST_TASKS)

        case task.command
        when "EDIT"
          execute_script_edit(task)
        when "RUN"
          execute_script_run(task)
        end
      end
    end



    def execute_script_run(task)
      [1,2].each do | pass |
        task.section.each do | line |
          line = "#{line}"

          line.strip!

          next if (line =~ /^#/)
          next if (line =~ /^\s*$/)

          directives = "#{line.slice!(/^[@-]+/)}"

          print "[maxe]\# #{line}\n" if (pass == 1 and $MAXE_PROMPT)

          if (pass == 2 and not $MAXE_DEBUG)
            print "[maxe]\# #{line}\n" if (directives.index('@') == nil)
            system(line)
            status = $?.exitstatus
            raise "command failed (exit status #{status})" if (status != 0 and directives.index('-') == nil)
          end
        end

        if (pass == 1 and $MAXE_PROMPT)
          print "\nPress ENTER to continue..."
          STDIN.gets
          print "\n"
        end
      end
    end



    def execute_script_edit(task)
      prop_file = task.header['FILE'][0]
      prop_areas = []
     task. header['AREA'].each do | area |
        prop_areas << Regexp.new(area, Regexp::MULTILINE)
      end
      prop_comment = task.header['COMMENT'][0]

      raise "missing FILE:" if (prop_file == nil)
      raise "no AREA: (minimum 1 required)" if (prop_areas.length <= 0)

      start_line = "#{prop_comment} #{task.id} GENERATED AUTOMATICALLY BY MAXE; DO NOT EDIT!"
      end_line = "#{prop_comment} END OF #{task.id} GENERATED AUTOMATICALLY BY MAXE; DO NOT EDIT!"

      prop_areas.insert(0, Regexp.new(/(\A.*?)(#{start_line}\n.+?\n#{end_line}\n)(.*\Z)/m))


      task.section.insert(0, start_line)
      task.section << end_line


      catch(:found) do
        file_contents = []
        file_contents = File::readlines(prop_file) if (File.exist?(prop_file))
        file_contents = file_contents.join()

        prop_areas.each do | area |
          match = file_contents.match(area).to_a

          if (match.length == 4)
            prefix = match[1]
            area = match[2]
            suffix = match[3]

            final = "#{prefix}"
            p (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
            final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
            final = final + task.section.join("\n")
            p (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
            final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
            final = final + suffix
            p (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
            final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)

            if ($MAXE_SHOW_DIFFS)
              diff_org = []
              diff_org = File::readlines(prop_file).join().split("\n") if (File::exist?(prop_file))
              diff_final = final.split("\n")

              print "Diff: #{prop_file}\n"
              print_diff(diff_org, diff_final)
            end

            if ($MAXE_PROMPT)
              print "\nPress ENTER to continue..."
              STDIN.gets
              print "\n"
            end

            if (not $MAXE_DEBUG)
              File::open(prop_file, File::RDWR | File::CREAT | File::TRUNC) do | file |
                file.print(final)
              end
            end

            throw :found
          end
        end

        raise "no matching area found in file '#{prop_file}'"
      end
    end
  end
end