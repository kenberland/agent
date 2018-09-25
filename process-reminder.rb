#!/usr/bin/env ruby

require 'csv'

csv_out = CSV.new($stdout)
csv_out << %w{greeting first last email} 

begin
  while(line = $stdin.readline) do
    line.scan(/^(.+)\s<(.+)>$/) do |m|
      names = m[0].split(/\s+/)
      csv_out << [names[0], names[1], m[1]]
    end
  end
rescue EOFError
end

