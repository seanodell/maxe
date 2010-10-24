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



  Task = Struct.new("Task", :script_name, :phase, :order, :command, :id, :provides, :depends, :desc, :header, :section)



  class Tasks
    def initialize
      @tasks = []
    end



    def load_script(script_name)
      match = script_name.match(/^(.+?)_(.+?)[\._].*$/)
      machine = match[1]
      machine = nil if (machine == 'common')
      phase = match[2]

      return if ($MAXE_PHASES.index(phase) == nil)
      return if (machine != nil and machine.index($MAXE_MACHINE) == nil)

      script = File::readlines("#{$MAXE_SCRIPTS_DIR}/#{script_name}").collect do | line |
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

            id = header['ID']
            raise "missing ID:" if (id == nil || id[0].empty?)
            id = id[0]

            archetype = header['ARCHETYPE']
            archetype = archetype != nil ? archetype[0] : nil

            desc = header['DESCRIPTION']
            desc = desc != nil ? desc[0] : nil

            depends = header['DEPEND']

            provides = header['PROVIDES']
            raise "missing PROVIDES:" if(provides == nil || provides[0].empty?)
            provides = provides[0]

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
            next if ($MAXE_ALL_PROVIDES != true and $MAXE_MACHINE_NEEDS.index(provides) == nil)
            next if (archetype != nil and archetype != $MAXE_MACHINE_ARCHETYPE)

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

            task = Task.new()
            task.script_name = script_name
            task.phase = phase
            task.order = order
            task.command = command
            task.id = id
            task.provides = provides
            task.depends = depends
            task.desc = desc
            task.header = header
            task.section = section
            @tasks << task
            
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
      phase_order = ['setup', 'install', 'config', 'restart']

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
        next if (task.depends == nil or task.depends.length <= 0)
        task.depends.each do | depend |
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
            if (task.depends == nil or task.depends.length <= 0)
              tasks << task
              ordered_tasks[index] = nil

              reverse_depend = reverse_depend_map[task.id]
              if (reverse_depend != nil) # if other tasks depended on this (reverse lookup)
                reverse_depend.each do | depend_task |
                  depend_task.depends.delete(task.id) # then delete those dependencies
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

      id_width = @tasks.collect{|t|t.id}.max{|a,b|a.length<=>b.length}.length
      prov_width = @tasks.collect{|t|t.provides}.max{|a,b|a.length<=>b.length}.length + 2

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
          print("    #{last_script_name}\n")
        end
        printf("        %-*s %5s: %-*s %s\n", id_width, task.id, "#{task.command}",
          prov_width, "[#{task.provides}]", task.desc)
      end
    end

    def print_diff(org_array, final_array)
      diff = Diff::LCS::diff(org_array, final_array)
      last_position = nil
      if (diff.length > 0)
        diff.each do | change_area |
          change_area.each do | change |
            if (last_position == nil || last_position < (change.position - 1))
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
        when "PROPS"
          execute_script_props(task)
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
            final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
            final = final + task.section.join("\n")
            final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
            final = final + suffix
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



    def execute_script_props(task)
      prop_file = task.header['FILE'][0]
      prop_comment = task.header['COMMENT'][0]
      prop_separator = task.header['SEPARATOR'][0]

      raise "missing FILE:" if (prop_file == nil)
      raise "missing SEPARATOR:" if (prop_separator == nil)

      note_line = "#{prop_comment} GENERATED AUTOMATICALLY BY MAXE (#{task.id}); DO NOT EDIT!"

      file_contents = []
      file_contents = File::readlines(prop_file) if (File.exist?(prop_file))
      file_contents = file_contents.join()

      file_contents.gsub!("#{note_line}\n", "")
      
      task.section.each do | line |
        next if (line =~ /^\s*$/)
        
        match = line.match(/^\s*(.+?)[ \t]*#{prop_separator}.+$/)
        raise "property missing separator: '#{line}'" if (match == nil)

        property = match[1]

        regexp = /(\A.*?^)(\s*(#{prop_comment})?[ \t]*#{property}\s*#{prop_separator}.*?$\n?)(.*\Z)/m
        match = file_contents.match(regexp)
        if (match)
          final = "#{match[1]}"
          final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
          final = final + "#{note_line}\n"
          final = final + line
          final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
          final = final + match[4]
          final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
          file_contents = final
        else
          final = file_contents
          final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
          final = final + "#{note_line}\n"
          final = final + line
          final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
          file_contents = final
        end
      end

      if ($MAXE_SHOW_DIFFS)
        diff_org = []
        diff_org = File::readlines(prop_file).join().split("\n") if (File::exist?(prop_file))
        diff_final = file_contents.split("\n")

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
          file.print(file_contents)
        end
      end
    end
  end
end