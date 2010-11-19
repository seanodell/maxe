class Array
  attr_reader :shift_count

  def shift
    @shift_count = 0 if (not defined?(@shift_count))

    if (length > 0)
      line = self[0]
      delete_at(0)
      @shift_count = @shift_count + 1
    end

    return line
  end
end
