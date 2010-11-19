module Maxe
  class Tasks

    def run_command(task)
      [1,2].each do | pass |
        task.body.each do | line |
          line = "#{line}"

          line.strip!

          next if (line =~ /^#/)
          next if (line =~ /^\s*$/)

          directives = "#{line.slice!(/^[@-]+/)}"

          print "[maxe]\# #{line}\n" if (pass == 1 and $MAXE_SHOW_WORK)

          if (pass == 2 and not $MAXE_DEBUG)
            print "[maxe]\# #{line}\n" if (directives.index('@') == nil)
            system(line)
            status = $?.exitstatus
            raise "command failed (exit status #{status})" if (status != 0 and directives.index('-') == nil)
          end
        end

        return if (pass == 1 and not test_conditions(task))

        if (pass == 1 and $MAXE_PROMPT)
          return if (prompt() == false)
        end
      end

      print "Success!\n\n"
    end

  end
end