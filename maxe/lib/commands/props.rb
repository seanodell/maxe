module Maxe
  class Tasks

    def props_command(task)
      prop_file = task.header['FILE'][0]
      prop_comment = task.header['COMMENT'][0]
      prop_separator = task.header['SEPARATOR'][0]
      prop_annotate = task.header['ANNOTATE'] == nil or (not task.header['ANNOTATE'][0] =~ /(0)|([Nn][Oo])|([Ff][Aa][Ll][Ss][Ee])|([Oo][Ff][Ff])/)

      raise "missing FILE:" if (prop_file == nil)
      raise "missing SEPARATOR:" if (prop_separator == nil)

      note_line = "#{prop_comment} GENERATED AUTOMATICALLY BY MAXE (#{task.id}); DO NOT EDIT!"

      file_contents = []
      file_contents = File::readlines(prop_file) if (File.exist?(prop_file))
      file_contents = file_contents.join()

      file_contents.gsub!("#{note_line}\n", "")

      task.body.each do | line |
        next if (line =~ /^\s*$/)

        match = line.match(/^\s*(.+?)[ \t]*#{prop_separator}.+$/)
        raise "property missing separator: '#{line}'" if (match == nil)

        property = match[1]

        # try first without the comment char
        regexp = /(\A.*?^)(\s*()#{property}\s*#{prop_separator}.*?$\n?)(.*\Z)/m
        match = file_contents.match(regexp)

        if (match == nil) # if no match, try with
          regexp = /(\A.*?^)(\s*(#{prop_comment})?[ \t]*#{property}\s*#{prop_separator}.*?$\n?)(.*\Z)/m
          match = file_contents.match(regexp)
        end

        if (match)
          final = "#{match[1]}"
          final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
          final = final + "#{note_line}\n" if (prop_annotate == true)
          final = final + line
          final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
          final = final + match[4]
          final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
          file_contents = final
        else
          final = file_contents
          final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
          final = final + "#{note_line}\n" if (prop_annotate == true)
          final = final + line
          final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
          file_contents = final
        end
      end

      if ($MAXE_SHOW_WORK)
        diff_org = []
        diff_org = File::readlines(prop_file).join().split("\n") if (File::exist?(prop_file))
        diff_final = file_contents.split("\n")

        print "Diff: #{prop_file}\n"
        print_diff(diff_org, diff_final)
      end

      return if (not test_conditions(task))

      if ($MAXE_PROMPT)
        return if (prompt() == false)
      end

      if (not $MAXE_DEBUG)
        File::open(prop_file, File::RDWR | File::CREAT | File::TRUNC) do | file |
          file.print(file_contents)
        end
      end

      print "Success!\n\n"
    end

  end
end