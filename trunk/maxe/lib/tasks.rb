module Maxe

  Task = Struct.new("Task", :script_name, :phase, :order, :command, :id, :provides, :depends, :desc, :header, :body)

  class Tasks
    def initialize
      @tasks = []
    end

    def load_script(script_name)
      match = script_name.match(/^(.+?)[\._].*$/)
      phase = match[1]

      return if ($MAXE_PHASES.index(phase) == nil)

      script = File::readlines("#{$MAXE_SCRIPTS_DIR}/#{script_name}").collect do | line |
        line.chomp
      end

      array = script

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
            raise "missing ID:" if (id == nil)
            id = id[0]

            archetype = header['ARCHETYPE']
            archetype = archetype[0] if (archetype != nil)
            desc = header['DESCRIPTION']
            desc = desc[0] if (desc != nil)
            depends = header['DEPEND']

            provides = header['PROVIDES']
            provides = provides[0] if(provides != nil)

            # collect body lines
            body = []

            if (boundary)
              catch(:found) do
                while (line = array.shift)
                  break if (line =~ /^\s*#{boundary}\s*$/)
                  body << line
                end

                raise "END: value '#{boundary}' not found" if (not line =~ /^\s*#{boundary}\s*$/)
              end
            end

            next if ($MAXE_TARGET_TASKS != nil and $MAXE_TARGET_TASKS.index(id) == nil)
            next if ($MAXE_ALL_PROVIDES != true and provides!= nil and $MAXE_MACHINE_NEEDS.index(provides) == nil)
            next if (archetype != nil and archetype != $MAXE_MACHINE_ARCHETYPE)

            collection = header['COLLECTION']
            collection = eval(collection[0]) if (collection != nil)
            collection = [] if (collection == nil)
            collection.compact!
            collection << nil if (collection.length == 0)

            initializes = header['INITIALIZE']
            initializes = [initializes] if (initializes != nil and not initializes.kind_of?(Array))

            collection.each do | item |
              $MAXE_ITEM = item

              $MAXE_TASK = Task.new()
              $MAXE_TASK.script_name = script_name.clone
              $MAXE_TASK.phase = phase.clone
              $MAXE_TASK.order = "#{order}".to_i
              $MAXE_TASK.command = command.clone
              $MAXE_TASK.id = id.clone
              $MAXE_TASK.provides = provides.clone if (provides != nil)
              $MAXE_TASK.depends = depends.clone if (depends != nil)
              $MAXE_TASK.desc = desc.clone if (desc != nil)
              $MAXE_TASK.header = header.clone

              initializes.each do | initialize |
                eval(initialize)

                $MAXE_TASK.header.keys.each do | name |
                  value = $MAXE_TASK.header[name]
                  $MAXE_TASK.header[name] = [value] if (not value.kind_of?(Array))
                end
              end if (initializes != nil)

              template = ERB.new(body.join("\n"), 0, "%<>")
              $MAXE_TASK.body = template.result.split("\n")

              @tasks << $MAXE_TASK
            end

            order = order + 1
          elsif (not line =~/^\s*$/)
            raise "'#{line}' unexpected"
          end
        end
      rescue Exception => e
        e.message << " at line #{array.shift_count} in '#{script_name}'"
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

      catch(:no_more_resolvable) do
        # keep trying so long as there are tasks left to add to the final list
        while (ordered_tasks.length > 0)
          catch(:retry_dependencies) do
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
                  throw :retry_dependencies # also throw to the outer loop again
                end
              end
            end
            # should only get here when the last run resolved no more dependencies.
            # if any tasks remain, that means they still had dependencies.
            # since no more dependencies can be resolved, these tasks are un-resolvable
            throw :no_more_resolvable

          end # end of catch(:retry_dependencies)

          ordered_tasks.compact!
        end # end of while loop
      end # end catch(:no_more_resolvable)

      ordered_tasks.compact!
      if (ordered_tasks.length > 0) # at least one task was left (must have dependencies)
        unresolved = []

        ordered_tasks.each do | task |
          unresolved += task.depends
        end

        print "WARNING: could not resolve dependencies: #{unresolved.join(', ')}\n"

        tasks += ordered_tasks
      end

      @tasks = tasks
    end



    def print_synopsis
      id_width = @tasks.collect{|t|t.id}.max{|a,b|a.length<=>b.length}.length
      prov_width = @tasks.collect{|t|t.provides}.max{|a,b|(a ? a : "*").length<=>(b ? b : "*").length}.length + 2

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
          prov_width, "[#{task.provides ? task.provides : '*'}]", task.desc)
      end
    end

    def print_diff(org_array, final_array)
      diff = Diff::LCS::diff(org_array, final_array)
      last_position = nil
      print "\n"
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
        print "No changes in file detected\n"
      end
    end



    def prompt()
      print $MAXE_DEBUG ? "\nIn debug mode; will not process task\n\nPress ENTER to continue..." : "\nProcess task? [y/N]: "
      ans = STDIN.gets
      print "\n"
      return ((not $MAXE_DEBUG) and ans =~ /^[yY]/) ? true : false
    end

    def test_conditions(task)
      conditions = task.header['CONDITION']
      return true if (conditions == nil)

      conditions.each do | condition |
        if (not eval(condition))
          print "Condition '#{condition}' evaluated to false; will not process task\n"
          if ($MAXE_PROMPT)
            print "\nPress ENTER to continue..."
            STDIN.gets
            print "\n"
          end
          return false
        end
      end

      return true
    end



    def execute
      sort_tasks

      if ($MAXE_SYNOPSIS)
        print_synopsis
        exit 0
      end

      @tasks.each do | task |
        print "Processing (#{task.phase}) #{task.command} '#{task.id}' in '#{task.script_name}'\n"

        command = method("#{task.command.downcase}_command")

        raise "no such command '#{command}'" if (command == nil)

        command.call(task)
      end
    end

  end

end