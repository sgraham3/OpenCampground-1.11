module MyLib
include ActionView::Helpers::NumberHelper

  # A utility method for cleaning up names for regex processing
  #
  def regex_clean(s)
    s = s.to_s
    s.to_s.gsub(/\(/, "\\(").gsub(/\)/, "\)")
  end

  def validEmail(address)
    ##########################################
    # is this apparently a valid email address?
    ##########################################
    return false if address.nil?
    name,at,host = address.partition('@')
    return false if name.empty?
    return false if at.empty?
    return false if host.empty?
    return true
  end

  def currentDate
    # logger.debug "\033[31m" + ' currentDate ' + "\033[0m"
    ##########################################
    # give date in timezone if zone is defined
    # otherwise give date without zone
    ##########################################
    Date.current
  rescue
    Date.today
  end

  def currentTime
    ##########################################
    # give time in timezone if zone is defined
    # otherwise give time without zone
    ##########################################
    Time.current
  rescue
    Time.now
  end

  def fmt_date( this_date, values = 3 )
    ##########################################
    # format a string from the date using the
    # current date format
    ##########################################
    @option = Option.first unless @option
    case values
    when 2
      this_date.strftime(@option.date_fmt.short_fmt)
    when 3
      this_date.strftime(@option.date_fmt.fmt)
    end
  end

  def self.included(base)
    # make this method available to views as a helper
    base.send :helper_method, :fmt_date if base.respond_to? :helper_method
  end

  def parse_date(date_string)
    #################################################
    # this method parses date strings using the 
    # date format in use.
    #################################################
    @option = Option.first unless @option
    Date.strptime(this_date,  @option.date_fmt.fmt)
  end

  def round_cents( amt=0.00 )
    return ((amt + 0.005)*100).to_i / 100.0
  end

  ########################################################################
  # this is copied from number_helper because helpers are not available in
  # the models.  Only number_to_currency and supporting defs are copied
  ########################################################################
  # Formats a +number+ into a currency string. You can customize the format
  # in the +options+ hash.
  # * <tt>:precision</tt>  -  Sets the level of precision, defaults to 2
  # * <tt>:unit</tt>  - Sets the denomination of the currency, defaults to "$"
  # * <tt>:separator</tt>  - Sets the separator between the units, defaults to "."
  # * <tt>:delimiter</tt>  - Sets the thousands delimiter, defaults to ","
  #
  #  number_to_currency(1234567890.50)     => $1,234,567,890.50
  #  number_to_currency(1234567890.506)    => $1,234,567,890.51
  #  number_to_currency(1234567890.506, :precision => 3)    => $1,234,567,890.506
  #  number_to_currency(1234567890.50, :unit => "&pound;", :separator => ",", :delimiter => "") 
  #     => &pound;1234567890,50
  def number_2_currency(number)
    precision = I18n.t 'number:currency.format.precision'
    unit      = I18n.t 'number:currency.format.unit'
    separator = I18n.t 'number:currency.format.separator'
    delimiter = I18n.t 'number:currency.format.delimiter'
    format    = I18n.t 'number:currency.format.format'
        
    begin
      number_to_currency(number, 
			:precision => I18n.t('number.currency.format.precision'),
			:unit      => I18n.t('number.currency.format.unit'),
			:separator => I18n.t('number.currency.format.separator'),
			:delimiter => I18n.t('number.currency.format.delimiter'),
			:format    => I18n.t('number.currency.format.format'))
  #  rescue
      #number
    end
  end

  def currency_2_number(cur)
    cur.gsub!(I18n.t('number.currency.format.delimiter'), '')
    cur.gsub!(I18n.t('number.currency.format.unit'), '')
    cur.gsub(I18n.t('number.currency.format.separator'), '.')
  end

  def do_delete
    # get the file name
    file_list = session[:file_list]
    id = params[:id].to_i
    debug params[:id]
    debug file_list.inspect
    if @os == "Windows_NT"
      fqfn = session[:dir].gsub("/","\x5c") + file_list[id]
    else
      fqfn = session[:dir] + file_list[id]
    end
    # delete the indicated file
    result = File::delete(fqfn)
    if result
      flash[:notice] = "#{fqfn} deleted"
      debug "#{fqfn} deleted"
    else
      flash[:error] = "#{fqfn} deletion failed"
      error "#{fqfn} deletion failed"
    end
    session[:file_list] = nil
  end

  def do_download
    file_list = session[:file_list]
    id = params[:id].to_i
    # session[:file_list] = nil
    if params[:dir] == 'backup'
      type = "application/bak"
      session[:next_action] = :manage_backups
    else
      type = "text/plain"
      session[:next_action] = :manage_logs
    end
    send_file params[:dir]+"/#{file_list[id]}", :filename => file_list[id], :type => type
  end

  def handle_files(dir, suffix)
    debug "generating new filename list for #{suffix} in #{dir}"
    @file_stats = Array.new
    # get a list of files
    Dir::chdir(dir)
    filenames = Dir["*.#{suffix}"]
    @file_list = filenames.sort_by {|filename| File.mtime(filename) }
    @file_list.each { |f| @file_stats << File.stat(f) }
    # debug "before: #{filenames}, after: #{@file_list}"
    Dir::chdir("..")
    session[:dir] = "#{dir}/"
    session[:file_list] = @file_list
  end

end
