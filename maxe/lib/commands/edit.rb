module Maxe
  class Tasks

    def edit_command(task)
      prop_file = task.header['FILE'][0]
      prop_areas = []
      task. header['AREA'].each do | area |
        prop_areas << Regexp.new(area, Regexp::MULTILINE)
      end
      prop_comment = task.header['COMMENT'][0]
      prop_annotate = task.header['ANNOTATE'] == nil or (not task.header['ANNOTATE'][0] =~ /(0)|([Nn][Oo])|([Ff][Aa][Ll][Ss][Ee])|([Oo][Ff][Ff])/)

      raise "missing FILE:" if (prop_file == nil)
      raise "no AREA: (minimum 1 required)" if (prop_areas.length <= 0)

      if (prop_annotate == true)
        start_line = "#{prop_comment} #{task.id} GENERATED AUTOMATICALLY BY MAXE; DO NOT EDIT!"
        end_line = "#{prop_comment} END OF #{task.id} GENERATED AUTOMATICALLY BY MAXE; DO NOT EDIT!"

        prop_areas.insert(0, Regexp.new(/(\A.*?)(^#{start_line}$.+?^#{end_line}\n)(.*\Z)/m))
        task.body.insert(0, start_line)
        task.body << end_line
      end


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
            final = final + task.body.join("\n")
            final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)
            final = final + suffix
            final = "#{final}\n" if (not final =~ /\A\s*\Z/ and not final =~ /\n\s*\Z/)

            if ($MAXE_SHOW_WORK)
              diff_org = []
              diff_org = File::readlines(prop_file).join().split("\n") if (File::exist?(prop_file))
              diff_final = final.split("\n")

              print "Diff: #{prop_file}\n"
              print_diff(diff_org, diff_final)
            end

            return if (not test_conditions(task))

            if ($MAXE_PROMPT)
              return if (prompt() == false)
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

      print "Success!\n\n"
    end
    
  end
end