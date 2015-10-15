#!/usr/bin/env ruby
require 'io/console'
require 'csv'
require 'net/smtp'
require 'sqlite3'
require 'date'
require 'mail'
require 'pry'
require 'action_view'

class EmailAgent

  # CREATE TABLE sent( created_at datetime, company varchar(255), subject varchar(255), to_addr varchar(255) unique, message text );
  attr_accessor :current_company, :current_message
  @@prompts = %w/@full_name @username @password/

  def initialize
    process_csv
    open_database
    puts_table_rows_confirmation
    @@prompts.each do |v| 
      v = v.to_sym
      instance_variable_set(v, get_value_for(v))
    end
    @from_addr = @full_name + " " + "<" + @username + ">"
  end

  def open_database
    @db = SQLite3::Database.new "db/agent.db"
  end

  def process_csv
    @csv_file_name = ARGV.shift
    raise "Need input file!" unless @csv_file_name
    read_and_parse_csv
  end

  def load_next_message
    message = @enumerator.next
    @current_company = message[:company]
    @current_message = construct_email(message)
  end

  def send_current_message
    puts "Sending message..."
    begin
      smtp = Net::SMTP.new 'smtp.gmail.com', 587
      smtp.enable_starttls
      smtp.start('grnds.com', @username, @password, :login) do |server|
        smtp.send_message(@current_message.to_s, @username, @current_message.to)
      end
      record_sending_in_db
      puts "Sent email to #{@current_message.to}"
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
    @db.execute("select count(*) from sent where to_addr=?", @current_message.to.first) do |row|
      puts "Already sent to #{@current_message.to.first}" if row.first != 0
      return row.first == 0 
    end
  end

  private

  def record_sending_in_db
    values = [DateTime.now.to_s, @current_company, @current_message.subject, @current_message.to, @current_message.to_s]
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

  def create_plaintext_message msg
    msg.gsub(/(\W\n)/,'\1'+"\n").split(/\n/).map{|e| ActionView::Base.new.word_wrap e}.join("\n")
  end

  def create_rich_message msg
    msg.split(/\n/).map{|e| "<div>#{ActionView::Base.new.word_wrap e}</div><br />"}.join("\n")
  end

  def construct_email message
    mail = Mail.new
    plain = Mail::Part.new
    rich = Mail::Part.new
    plain.body = create_plaintext_message message[:message]
    rich.content_type = 'text/html; charset=UTF-8'
    rich.body = create_rich_message message[:message]
    mail.text_part = plain
    mail.html_part = rich

    mail.from = @from_addr
    mail.to = message[:to]
    mail.subject = message[:subject]

    mail
  end

end

agent = EmailAgent.new
begin
  while agent.load_next_message
    puts
    next unless agent.can_send?
    puts "*" * 40
    puts agent.current_message.to_s
    print "Send to #{agent.current_message.to.first} ( #{agent.count_of_emails_to_company} emails to #{agent.current_company} )? (y/n): "
    confirm = gets.chomp.downcase
    #STDIN.noecho(&:gets).chop.downcase

    if confirm == 'y'
      agent.send_current_message
    else
      puts "Not sent."
    end
  end
rescue StopIteration

end
