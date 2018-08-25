#!/usr/bin/env ruby

require 'rubygems'
require 'bundler'
Bundler.setup(:default, :ci)

require 'action_view'
require 'csv'
require 'date'
require 'erb'
require 'io/console'
require 'mail'
require 'net/smtp'
require 'nokogiri'
require 'pry'
require 'pry-byebug'
require 'sqlite3'
require 'openssl'
require 'base64'

def hex_to_bin(str)
  [str].pack "H*"
end

def bin_to_hex(str)
  str.unpack('C*').map{ |b| "%02X" % b }.join('')
end

KEY = hex_to_bin(Digest::SHA1.hexdigest('83V3jg%@FOcjskHb#')[0..32])

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
    recip = @enumerator.next
    @current_message = construct_email(recip)
  end

  def send_current_message
    puts "Sending message..."
    begin
      smtp = Net::SMTP.new 'localhost', 587
      smtp.start('localhost') do |server|
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

  def aes(m,k,t)
    (aes = OpenSSL::Cipher::Cipher.new('aes-256-cbc').send(m)).key = Digest::SHA256.digest(k)
    aes.update(t) << aes.final
  end

  def encrypt(key, text)
    aes(:encrypt, key, text)
  end

  def decrypt(key, text)
    aes(:decrypt, key, text)
  end

  def create_plaintext_message message
    body = File.read("message.txt.erb")
    template = ERB.new(body)
    template.result(binding)
  end

  def create_rich_message message
    body = File.read("message.html.erb")
    template = ERB.new(body)
    template.result(binding)
  end

  def construct_email message
    plaintext = "#{message[:first]} #{message[:last]} <#{message[:email]}>"
    message[:cipher_text] = Base64.urlsafe_encode64(encrypt(KEY,plaintext))

    mail = Mail.new
    mail.to = "#{message[:first]} #{message[:last]} <#{message[:email]}>"
    mail.subject = "Invitation to Harry Waterman's Bar Mitzvah"
    mail.from = @from_addr
    mail.content_type = 'multipart/alternative'

    text_part = Mail::Part.new
    text_part.body = create_plaintext_message(message)
    mail.add_part(text_part)

    other_part = Mail::Part.new
    other_part.content_type = 'multipart/related;'
    other_part.add_file('./invite-small.jpg')
    message[:image] = other_part.attachments.first.cid

    html_part = Mail::Part.new
    html_part.content_type = 'text/html; charset=UTF-8'
    html_part.body = create_rich_message message
    other_part.add_part(html_part)
    mail.add_part(other_part)

    mail
  end

end

agent = EmailAgent.new
begin
  while agent.load_next_message
    puts
    next unless agent.can_send?
    puts "*" * 40
    # puts agent.current_message.to_s
    print "Sending to #{agent.current_message.to.first} ( #{agent.count_of_emails_to_company} emails to #{agent.current_company} )? (y/n): "
    #confirm = gets.chomp.downcase
    #STDIN.noecho(&:gets).chop.downcase
    #if confirm == 'y'
      agent.send_current_message
    #else
    #  puts "Not sent."
    #end
    sleep 1.0
  end
rescue StopIteration

end
