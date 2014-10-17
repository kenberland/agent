#!/usr/bin/env ruby
require 'io/console'
require 'csv'
require 'net/smtp'
require 'sqlite3'
require 'date'

class EmailAgent

  # CREATE TABLE sent( created_at datetime, company varchar(255), subject varchar(255), to_addr varchar(255) unique, message text );
  attr_accessor :current_company, :current_message_to, :current_message_body

  def initialize
    @csv_file_name = ARGV.shift
    raise "Need input file!" unless @csv_file_name
    @db = SQLite3::Database.new "db/agent.db"
    puts_table_rows_confirmation
    instance_variables = %w/@full_name @username/
    instance_variables.each do |v| 
      v = v.to_sym
      instance_variable_set(v, get_value_for(v))
    end
    @password = get_password
    print "\n"
    read_and_parse_csv
  end

  def load_next_message
    message = @enumerator.next
    @current_subject = message[:subject]
    @current_company = message[:company]
    @current_message_to = /<(.*)>/.match(message[:to])[1]
    @current_message_body = message[:message]
    @current_message_string = construct_email(message)
  end

  def send_current_message
    puts "Sending message..."
    begin
      smtp = Net::SMTP.new 'smtp.gmail.com', 587
      smtp.enable_starttls
      smtp.start('grnds.com', @username, @password, :login) do |server|
        smtp.send_message(@current_message_string, @username, @current_message_to)
      end
      record_sending_in_db
      puts "Sent email to #{@current_message_to}"
    rescue Exception => e
      puts "EROR SENDING: #{e.to_s}"
    end
  end

  def count_of_emails_to_company
    @db.execute( "select count(*) from sent where company=?", @current_company ) do |row|
      return row.first
    end
  end

  def can_send?
    @db.execute("select count(*) from sent where to_addr=?", @current_message_to) do |row|
      puts "Already sent to #{@current_message_to}" if row.first != 0
      return row.first == 0 
    end
  end

  private 

  def record_sending_in_db
    values = [DateTime.now.to_s, @current_company, @current_subject, @current_message_to, @current_message_string]
    @db.execute("insert into sent values ( ?, ?, ?, ?, ? )", values)
  end
  
  def puts_table_rows_confirmation
    @db.execute( "select count(*) from sent" ) do |row|
      puts "Found #{row.first} in sent table"
    end
  end

  def get_value_for key
    env_key = "AGENT_DEFAULT_#{key.to_s.upcase.gsub!('@','')}"
    default = ENV[env_key]
    print "#{key} (default #{default}): "
    user_value = gets.chop
    user_value.length > 0 ? user_value : default
  end

  def get_password
    print "password: "
    STDIN.noecho(&:gets).chop
  end

  def set_enumerator
    @enumerator = @csv.each
  end

  def read_and_parse_csv
    csv_string = File.read(@csv_file_name)
    @csv = []
    CSV.parse(csv_string, :headers => true, :header_converters => :symbol, :converters => :all) do |row|
      @csv << Hash[row.headers[0..-1].zip(row.fields[0..-1])]
    end
    set_enumerator
  end

  def construct_email message
    s = "From: #{@full_name} <#{@username}>\n"
    s.concat "To: #{@current_message_to}\n"
    s.concat "Subject: #{@current_subject}\n"
    s.concat "Date: #{DateTime.now.rfc2822.to_s}"
    s.concat "\n"
    s.concat "#{@current_message_body.gsub(/(\W\n)/,'\1'+"\n")}"
  end

end

agent = EmailAgent.new

begin
  while agent.load_next_message

    next unless agent.can_send?

    puts agent.current_message_body
    puts "Send to #{agent.current_message_to} ( #{agent.count_of_emails_to_company} emails to #{agent.current_company} )? (y/n): "
    confirm = gets.chomp.downcase

    if confirm == 'y'
      agent.send_current_message
    else
      puts "Not sent."
    end
    
  end
rescue StopIteration

end
