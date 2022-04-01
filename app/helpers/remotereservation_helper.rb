
module RemotereservationHelper
  
  def blackout_dates
    str = ''
    Blackout.active.each {|b| str << "<div style=\"text-indent: 5em\">blacked out #{DateFmt.format_date(b.startdate)} to #{DateFmt.format_date(b.enddate)}</div>"}
    if str.blank?
      return str
    else
      return '<div><b>Remote reservations are not availailable in blackout dates. Please call:' + str + '</div>'
    end
  end
      
  def deposit_details(dep)
    # logger.debug dep.inspect
    if dep[:custom] == 'Full'
      return "\n"
    else
      return "<tr><td>#{dep[:custom]}</td>#{spacing_for_charges}<td align=\"right\">" +
	      number_2_currency(dep[:charge]) + "</td></tr>\n"
    end
  end

  def payment_details(pmt)
    # cardtype number date [user] memo
    memo = pmt.memo? ? pmt.memo : ""
    card = pmt.creditcard_id? ? pmt.creditcard.name : ""
    # date = pmt.pmt_date ? DateFmt.format_date(pmt.pmt_date) : ""
    date = DateFmt.format_date(pmt.pmt_date)

    card + ' ' + date + ' ' + memo
  end

  def fd_charges(res)
    # generate lines like
    # <input name="x_line_item" value="
    #                         Item ID<|>
    #                         Item Title<|>
    #			      Item Description<|>
    #			      Quantity<|>
    #			      Unit Price<|>
    #			      Taxable<|> Y or N
    #			      Product Code<|>
    #			      Commodity Code<|>
    #			      Unit of Measure<|>
    #			      Tax Rate<|>
    #			      Tax Type<|>
    #			      Tax Amount<|>
    #			      Discount Indicator<|>
    #			      Discount Amount<|>
    #			      Line Item Total" type="hidden">
    #
    str = ''
    counter = 0
    logger.debug "#{res.charges.size} charges"
    charges = 0.0
    res.charges.each do |chg|
      # Item ID
      counter += 1
      logger.debug counter.to_s
      str << '<input name="x_line_item" value = "' + counter.to_s + '<|>' 
      # Item Title and Item Description
      season_count = Season.count(:conditions => ["active = ?", true])
      case chg.charge_units
      when Charge::DAY
	str <<  chg.season.name + ' ' if season_count > 1
	str <<  I18n.t('reservation.Days') + ' ' + DateFmt.format_date(chg.start_date) + '-' + DateFmt.format_date(chg.end_date) + '<|>' 
	str <<  chg.season.name + ' ' if season_count > 1
	str <<  I18n.t('reservation.Days') + ' ' + DateFmt.format_date(chg.start_date) + '-' + DateFmt.format_date(chg.end_date) + '<|>' 
	logger.debug 'days'
      when Charge::WEEK
	str <<  chg.season.name + ' ' if season_count > 1
	str << I18n.t('reservation.Weeks') + ' ' + DateFmt.format_date(chg.start_date) + '-' + DateFmt.format_date(chg.end_date) + '<|>' 
	str <<  chg.season.name + ' ' if season_count > 1
	str << I18n.t('reservation.Weeks') + ' ' + DateFmt.format_date(chg.start_date) + '-' + DateFmt.format_date(chg.end_date) + '<|>' 
	logger.debug 'weeks'
      when Charge::MONTH
	str <<  chg.season.name + ' ' if season_count > 1
	str << I18n.t('reservation.Months') + ' ' + DateFmt.format_date(chg.start_date) + '-' + DateFmt.format_date(chg.end_date) + '<|>' 
	str <<  chg.season.name + ' ' if season_count > 1
	str << I18n.t('reservation.Months') + ' ' + DateFmt.format_date(chg.start_date) + '-' + DateFmt.format_date(chg.end_date) + '<|>' 
	logger.debug 'months'
      end
      # quantity
      str <<  sprintf("%0.2f", chg.period) + '<|>' 
      # unit price
      str << sprintf('%0.2f',chg.rate) + '<|>'
      # taxable?, product code, commodity code, unit of measure, tax rate, tax amount, discount indicator, discount amount
      str << 'N<|><|><|><|><|><|><|>0.00<|>'
      # line item total
      str << sprintf('%0.2f', chg.amount)
      str << '" type="hidden">' + "\n"
      charges += chg.amount
    end
    res.extra_charges.each do |ext|
      if ext.extra.extra_type == Extra::OCCASIONAL
	if ext.charge != 0.0
	  counter += 1
	  # Item ID
	  str << '<input name="x_line_item" value = "' + counter.to_s + '<|>' 
	  # Item Title and Item Description
	  str << ext.extra.name + '<|>' + ext.extra.name + '<|>'
	  # quantity
	  str << ext.number.to_s + '<|>'
	  # unit price
	  str << sprintf('%0.2f', ext.extra.charge) + '<|>'
	  # taxable?, product code, commodity code, unit of measure, tax rate, tax amount, discount indicator, discount amount
	  str << 'N<|><|><|><|><|><|><|>0.00<|>'
	  # line item total
	  str << sprintf('%0.2f', ext.charge) + '" type="hidden">' + "\n"
	  charges += ext.charge
	end
      else
        # Item Title and Item Description
        if ext.days > 0
          counter += 1
	  # Item ID
          str << '<input name="x_line_item" value = "' + counter.to_s + '<|>' 
          # Item Title and Item Description
          str << ext.extra.name + ' days' + '<|>' + ext.extra.name + ' days' + '<|>'
          # quantity
          if(ext.extra.extra_type == Extra::COUNTED) 
	    str << (ext.days * ext.number).to_s + '<|>'
	  else
	    str << ext.days.to_s  + '<|>'
	  end
          # unit price
          str << sprintf('%0.2f', ext.extra.daily) + '<|>'
          # taxable?, product code, commodity code, unit of measure, tax rate, tax amount, discount indicator, discount amount
          str << 'N<|><|><|><|><|><|><|>0.00<|>'
          # line item total
          str << sprintf('%0.2f', ext.daily_charges) + '" type="hidden">' + "\n"
          charges += ext.daily_charges
        end
        if ext.weeks > 0
          counter += 1
	  # Item ID
          str << '<input name="x_line_item" value = "' + counter.to_s + '<|>' 
          # Item Title and Item Description
          str << ext.extra.name + ' weeks' + '<|>' + ext.extra.name + ' weeks' + '<|>'
          # quantity
          if(ext.extra.extra_type == Extra::COUNTED) 
	    str << (ext.weeks * ext.number).to_s + '<|>'
	  else
	    str << ext.weeks.to_s  + '<|>'
	  end
          # unit price
          str << sprintf('%0.2f', ext.extra.weekly) + '<|>'
          # taxable?, product code, commodity code, unit of measure, tax rate, tax amount, discount indicator, discount amount
          str << 'N<|><|><|><|><|><|><|>0.00<|>'
          # line item total
          str << sprintf('%0.2f', ext.weekly_charges) + '" type="hidden">' + "\n"
          charges += ext.weekly_charges
        end
        if ext.months > 0
          counter += 1
	  # Item ID
          str << '<input name="x_line_item" value = "' + counter.to_s + '<|>' 
          # Item Title and Item Description
          str << ext.extra.name + ' months' + '<|>' + ext.extra.name + ' months' + '<|>'
          # quantity
          if(ext.extra.extra_type == Extra::COUNTED) 
	    str << (ext.months * ext.number).to_s + '<|>'
	  else
	    str << ext.months.to_s  + '<|>'
	  end
          # unit price
          str << sprintf('%0.2f', ext.extra.monthly) + '<|>'
          # taxable?, product code, commodity code, unit of measure, tax rate, tax amount, discount indicator, discount amount
          str << 'N<|><|><|><|><|><|><|>0.00<|>'
          # line item total
          str << sprintf('%0.2f', ext.monthly_charges) + '" type="hidden">' + "\n"
          charges += ext.monthly_charges
        end
      end
    end
    res.taxes.each do |t|
      counter += 1
      str << '<input name="x_line_item" value = "' + counter.to_s + '<|>' 
      # Item Title and Item Description
      str << t.name + '<|>'
      str << t.name + '<|>'
      # quantity
      str <<  '1.0<|>' 
      # unit price
      str << sprintf('%0.2f',t.amount) + '<|>'
      # taxable?, product code, commodity code, unit of measure, tax rate, tax amount, discount indicator, discount amount
      str <<  'N<|><|><|><|><|><|><|>0.00<|>'
      # line item total
      str << sprintf('%0.2f', t.amount)
      str << '" type="hidden">' + "\n"
      charges += t.amount
    end
    str << '<input name="x_amount" value="' + sprintf("%0.2f", charges) + '" type="hidden">' + "\n"
    hash = @integration.firstdatae4_hash(@reservation, charges)
    str << '<input name="x_fp_hash" value="' + hash + '" type="hidden">'
    logger.debug str
    return str
  end

  def header
    debug 'header'

    av_init
    # ret_str = get_header_months
    ret_str = get_header_days
  end

  def av_init
    debug 'av_init'
    @closedDays = 0
    @startDate = currentDate - @option.lookback
    # days = @option.sa_columns + @option.lookback
    days = @option.custom_sa_columns + @option.lookback
    if @option.use_closed?
      @closedType = Summer
      @closedStart = @option.closed_start.change(:year => currentDate.year) 
      @closedEnd = @option.closed_end.change(:year => currentDate.year)
      if @closedStart > @closedEnd
        debug "closed start is #{@closedStart} and closed end is #{@closedEnd} giving type Winter"
        @closedType = Winter
	if @startDate < @closedEnd
	  @startDate = @closedEnd
	end
        @closedEnd = @closedEnd.change(:year => currentDate.year + 1)
      else
        debug "closed start is #{@closedStart} and closed end is #{@closedEnd} giving type Summer"
      end
      date = @startDate
      cs = @closedStart
      ce = @closedEnd
      day_cnt = 0
      while day_cnt < days
        if date < cs
	  day_cnt += 1
	elsif date == ce
	  ce = ce.change(:year => ce.year + 1)
	  cs = cs.change(:year => cs.year + 1)
	else
	  @closedDays += 1
	end
	date = date.succ
      end
      @endDate = date
      debug "closed from #{@closedStart} to #{@closedEnd} for #{@closedDays} days type #{@closedType}"
    else
      @endDate = @startDate + days
    end
    debug "starting at #{@startDate} and ending at #{@endDate}"
  end

  def get_header_months
    hdr_init
    ret_str = '<tr id="lockedHeadMonth"><th class="av_date" style="border:1px solid white;background:#666666;text-align:center;color:white">'
    if @option.max_spacename > 5
      spacer = ((@option.max_spacename - 4)/1.5).to_i
      ret_str << '&nbsp;' * spacer
      ret_str << I18n.t('reservation.Space')
      ret_str << '&nbsp;' * spacer
    else 
      ret_str << 'Space'
    end
    ret_str << '</th>'
    # print out the months
    date = @startDate 
    first_closed = true
    day = Date.new
    debug "get_header_months enddate is #{@endDate}"
    while date < @endDate 
      # if @option.use_closed? && date > @cs && date > @ce
      if @option.use_closed? && date > @cs
        # we are past the original dates...up start and end by a year
        @cs = @cs.change(:year => @cs.year + 1)
        @ce = @ce.change(:year => @ce.year + 1)
      end
      hdr_count,day = hdr_day_count(date)
      # print out as month
      debug "date is #{date}, next day to output is #{day} header count is #{hdr_count}"
      if hdr_count > 0
	if hdr_count < 4
	  ret_str << "<th class=\"av_date\" colspan=\"#{hdr_count}\" style=\"text-align:center;background:#666666;border:1px solid white;color:white\"></th>"
	else
	  ret_str << "<th class=\"av_date\" colspan=\"#{hdr_count}\" style=\"text-align:center;background:#666666;border:1px solid white;color:white\">#{I18n.l(date,:format => :month)}</th>"
	end
	date = day
      else
        date = @ce
      end
      if @option.use_closed? && (@ce == date)
	      ret_str << '<th class="av_date" style="border:1px solid black;background-color:DarkGrey;color:white;text-align:center"></th>'
      end
    end
    ret_str << "</tr>\n"
  end

  def hdr_init
    if @option.use_closed? 
      @cs = @option.closed_start.change(:year => currentDate.year)
      @ce = @option.closed_end.change(:year => currentDate.year)
      debug "start date is #{@startDate} and @ce is #{@ce}"
      if @startDate > @ce && @closedType == Winter
	@ce = @ce.change(:year => currentDate.year + 1)
	debug "winter: start date is #{@startDate} and @ce is #{@ce}"
      end
    end
  end

  def hdr_day_count(this_date)
    if @option.use_closed? 
      debug "hdr_day_count #{this_date}, @cs = #{@cs}, @ce = #{@ce}"
      if this_date > @cs && this_date <= @ce
	count = 0
	day = @ce + 1
      elsif @cs.month == this_date.month
        if @ce.month == @cs.month
	  count = this_date.end_of_month - this_date - closedDays + 1
	  day = this_date.end_of_month + 1
	else
	  count = @cs - this_date
	  day = @ce
	end
      else
	count = this_date.end_of_month - this_date + 1
	day = this_date.end_of_month + 1
      end
    else
      count = this_date.end_of_month - this_date + 1
      day = this_date.end_of_month + 1
    end
    return count,day
  end

  def get_header_days
    hdr_init
    # print out the days
    date = @startDate 
    first_closed = true
    ret_str = '<div id="lockedHeadDay" class="overflow-hidden"><div id="flexDiv" class="d-flex overflow-auto"><div class="av_date header-th" id="stickyTh" style="border:1px solid white;background:#666666;"></div>'
    # debug "get_header_days enddate is #{@endDate}"
    while date < @endDate 
      if @option.use_closed? 
        if date > @cs && date > @ce
          # we are past the original dates...up start and end by a year
          @cs = @cs.change(:year => @cs.year + 1)
          @ce = @ce.change(:year => @ce.year + 1)
        end
        if  (date+1) > @cs && (date+1) < @ce
          ret_str << '<div class="av_date header-th" style="border:1px solid white;background:#666666"></div>'
          # debug "closed #{date}"
          date = @ce
          next
        end
      end
      strmonth = Date::MONTHNAMES[date.month];
      if date == currentDate
	      ret_str << '<div class="av_date header-th"  style="border:1px solid white;background:lightGreen;text-align:center;color:white;"><span year=' + date.year.to_s + '></span><div>' + date.strftime("%a") + '</div><div>' + date.strftime("%d") + '</div><div>' + strmonth[0..2] + '</div></div>'
      elsif date.wday == 0 || date.wday == 6
	      ret_str << '<div class="av_date header-th"  style="border:1px solid white;background:#666666;color:white;text-align:center"><span year=' + date.year.to_s + '></span><div>' + date.strftime("%a") + '</div><div>' + date.strftime("%d") + '</div><div>' + strmonth[0..2] + '</div></div>'
      else
        ret_str << '<div class="av_date header-th"  style="border:1px solid white;background:#666666;color:white;text-align:center"><span year=' + date.year.to_s + '></span><div>' + date.strftime("%a") + '</div><div>' + date.strftime("%d") + '</div><div>' + strmonth[0..2] + '</div></div>'
      end   
      date = date.succ 
    end
    ret_str << "</div></div>\n"
  end

  def available()
    #############################################
    # res_array is a hash of arrays of reservations
    # with the key being the space_id.  Each
    # array of reservations is sorted by startdate
    #############################################
    debug 'available'
    ret_str = ''
    av_init

    res = Reservation.all( :conditions => [ "(enddate >= ? or checked_in = ?) and confirm = ? and archived = ?",currentDate, true, true, false],
    :include => ['camper'],
			   :order => "space_id,startdate ASC")
    # check for conflicts aka double booking
    res.each do |r|
      sp = Space.confirm_available r.id, r.space_id, r.startdate, r.enddate
      if sp.size > 0
        sp.each do |s|
          if flash[:error]
            flash[:error] +=  " Conflict between #{r.id} and #{s.id}"
          else
            flash[:error] =  "Conflict between #{r.id} and #{s.id}"
          end
        end
      end
    end
    res_hash = res.group_by{|sp|sp.space_id}

    Space.active(:order => 'position').each do |space|
      date = @startDate
      ret_str << '<tr>'
      # start with the space name
      if space.unavailable?
	        ret_str << '<td class="av_space"  style="border:1px solid #D6D6D6;background:#666666;text-align:center;color:white">' +  space.name + '</td>' 
      else
	      ret_str << '<td class="av_space"  style="border:1px solid #D6D6D6;background:#666666;text-align:center;color:white">' +  space.name + '</td>'
      end
      if @option.use_closed?
	@cs = @closedStart
	@ce = @closedEnd
      end
      if res_hash.has_key? space.id
	debug "\nspace #{space.name} has reservations"
	debug "@cs is #{@cs}, @ce is #{@ce}" if @option.use_closed?
	debug "available enddate is #{@endDate}"
	while date < @endDate 
	  debug "date is #{date}"
	  if @option.use_closed? && (date >= @cs && date < @ce)
	    debug "in closed date = #{date}"
	    ret_str << handle_cells(date, @ce)
	    date = @ce
	  end
	  if res_hash[space.id][0] && (date >= res_hash[space.id][0].startdate) # && (date < res_hash[space.id][0].enddate)
	    debug 'got new reservation'
	    r = res_hash[space.id].shift # shift it out
	    if r.enddate <= @startDate
	      debug "enddate #{r.enddate} for #{r.id} before startdate #{@startdate}"
	      next
	    end
	    cnt = day_count(r,date)
	    if cnt == 0
	      debug "skipping res #{r.id} with count 0"
	      next
	    end
	    name = trunc_name(cnt, r)
	    ret_str << "<td colspan=\"#{cnt}\" align=\"center\" "
	    if r.checked_in
          ret_str << 'style="background-color:lightGrey">' # occupied    
	    else
	      if currentDate > r.startdate
            ret_str << 'style="background-color:lightGrey">' # overdue
	      else
            ret_str << 'style="background-color:lightGrey">' # reserved
	      end
	    end
	    title = r.camper.full_name + ', '
	    title << I18n.l(r.startdate, :format => :short) + I18n.t('reservation.To') + I18n.l(r.enddate, :format => :short)
      ret_str << "<a href=\"/reservation/show?reservation_id=#{r.id}\" title=\"#{title}\">#{}</a>"
	    if @option.use_closed && r.enddate > @cs && r.enddate < @ce
	      ret_str << handle_cells(@cs, @ce)
	      date = @ce
	    else
	      date = r.enddate
	    end
	  else # open
	    debug 'open'
	    if res_hash[space.id].empty?
	      debug 'no more reservations'
	      ret_str << handle_cells(date, @endDate)
	      date = @endDate
	      debug "set date to #{date}"
	    else
	      rh = res_hash[space.id][0]
	      if @option.use_closed?
		if rh.startdate >= @cs && rh.startdate < @ce 
		  debug "skipping #{rh.id} with startdate #{rh.startdate} and enddate #{rh.enddate}"
		  sd = @cs 
		else
		  sd = rh.startdate
	        end
	      else
		sd = rh.startdate
	      end
	      ret_str << handle_cells(date, sd)
	      date = sd
	      debug "set date to #{date}"
	    end
	  end 
	end
	if @option.use_closed && date >= @ce
	  @cs = @cs.change(:year => @cs.year + 1)
	  @ce = @ce.change(:year => @ce.year + 1)
	  debug "changing cs year to #{@cs.year}"
	end
      else
	debug "\nspace #{space.name} no reservations"
        # no reservations on this space
	debug "available enddate is #{@endDate}"
	ret_str << handle_cells(@startDate, @endDate)
      end
      ret_str << "</tr>\n"
    end
    return ret_str
  end

  def handle_cells(sd, ed)
    debug "handle_cells sd=#{sd}, ed=#{ed}"
    ret_str = ''
    if ed > @endDate
      debug "end date adjusted from #{ed} to #{@endDate}"
      ed = @endDate
    end
    if sd >= ed
      debug "return because start date #{sd} >= end date #{ed}"
      return ret_str
    end

    date = sd
    while date < ed
      if @option.use_closed && date > @ce
	@cs = @cs.change(:year => @cs.year + 1)
	@ce = @ce.change(:year => @ce.year + 1)
	debug "changing cs year to #{@cs.year}"
      end
      debug date.to_s
      if @option.use_closed
	debug 'using closed dates'

	if date == currentDate
	  debug 'currentDate'
	    ret_str << '<td style="border:1px solid #D6D6D6;"></td>'
	  date += 1
	elsif date < @cs && ed < @cs
	  # case 1 between closures
	  debug 'case 1'
	  if date > currentDate || ed < currentDate
	    ret_str << output_empty(date, (ed - date).to_i)
	    date = ed
	  else
	    ret_str << output_empty(date, (currentDate - date).to_i)
	    date = currentDate
	  end
	elsif date < @cs && ed >= @ce
	  # case 5 spanning closure
	  debug 'handle_cells: case 5 output grey'
	  if date > currentDate || ed < currentDate
	    ret_str << output_empty(date, (@cs - date).to_i)
	    ret_str << '<td style="border:1px solid black;background-color:DarkGrey"></td>'
	    date = @ce 
	  else
	    ret_str << output_empty(date, (currentDate - date).to_i)
	    date = currentDate
	  end
	elsif date < @cs && ed >= @cs
	  # case 3 start before, end in closure
	  debug 'handle_cells: case 3 output grey'
	  if date > currentDate || ed < currentDate || (currentDate > @cs && currentDate < @ce)
	    ret_str << output_empty(date, (@cs - date).to_i)
	    # ret_str << '<td style="border:1px solid black;background-color:DarkGrey"></td>'
	    date = @ce
	  else
	    ret_str << output_empty(date, (currentDate - date).to_i)
	    date = currentDate
	  end
	elsif date >= @ce 
	  # case 2 between closures
	  debug 'case 2'
	  cs_ = @cs.change(:year => @cs.year + 1)
	  if currentDate > date && currentDate <= ed  && currentDate < cs_
	    out_date = currentDate > cs_ ? cs_ - 1 : currentDate
	    ret_str << output_empty(date, (out_date - date).to_i)
	    date = out_date
	  else
	    out_date = ed > cs_ ? cs_ - 1 : ed
	    ret_str << output_empty(date, (out_date - date).to_i)
	    date = out_date
	  end
	elsif date > @cs && ed >= @ce
	  # case 4 start in closure
	  debug 'handle_cells: case 4 output grey'
	  if date > currentDate || ed < currentDate
	    ret_str << '<td style="border:1px solid black;background-color:DarkGrey"></td>'
	    date = @ce
	  else
	    ret_str << output_empty(date, (currentDate - date).to_i)
	    date = currentDate
	  end
	elsif date >= @cs && date < @ce
	  # case 6 within closure
	  debug 'handle_cells: case 6 output grey'
	  ret_str << '<td style="border:1px solid black;background-color:DarkGrey"></td>'
	  date = @ce
	else
	  # we should never get here
	  debug "@cs is #{@cs}, @ce = #{@ce}"
	  raise 'error' 
	end

        debug "using closed, next date is #{date}"
      else # no closed
	if date > currentDate
	  debug "handle_cells: after currentDate, output_empty(#{date}, #{(ed - date).to_i})"
	  ret_str << output_empty(date, (ed - date).to_i)
	  date = ed
	elsif ed < currentDate
	  debug "handle_cells: before currentDate, output_empty(#{date}, #{(ed - date).to_i})"
	  ret_str << output_empty(date, (ed -date).to_i)
	  date = ed
	elsif date == currentDate # current date
	  debug 'handle_cells: outside of closed: date == currentDate'
	  ret_str << '<td style="border:1px solid #D6D6D6;"></td>'
	  date = currentDate + 1
	else # date < currentDate && ed >= currentDate # spans current
	  debug "handle_cells: starts before and spans currentDate, output_empty(#{date}, #{(currentDate - date).to_i})"
	  ret_str << output_empty(date, (currentDate - date).to_i)
	  date = currentDate
	end
      end
    end
    return ret_str
  end

  def output_empty(in_sd, count)
    # sd = (in_sd.class == 'Date' ? in_sd : Date.parse(in_sd))
    debug "output_empty sd = #{in_sd} count = #{count}"
    sd = in_sd
    ret_str = ''
    while count > 0
      # debug "sd is #{sd}, day = #{sd.wday} and count is #{count}"
      case sd.wday
      when 6 # saturday
	# debug 'saturday'
	if count > 6
	  ret_str << '<td style="border:1px solid #D6D6D6;"></td><td style="border:1px solid #D6D6D6;"></td><td></td><td></td><td></td><td></td><td></td>'
	  count -= 7
	  sd += 7.days
	else
	  ret_str << '<td style="border:1px solid #D6D6D6;"></td>'
	  count -= 1
	  sd += 1.days
	end
      when 0 # sunday
	# debug 'sunday'
	cnt = count < 6 ? count : 6
	ret_str << '<td style="border:1px solid #D6D6D6;"></td>' + '<td></td>' * (cnt - 1)
	count -= cnt
	sd += cnt.days
      when 1 # monday
	# debug 'monday'
	cnt = count < 5 ? count : 5
	ret_str << '<td></td>' * cnt
	count -= cnt
	sd += cnt.days
      when 2 # tuesday
	# debug 'tuesday'
	cnt = count < 4 ? count : 4
	ret_str << '<td></td>' * cnt
	count -= cnt
	sd += cnt.days
      when 3 # wednesday
	# debug 'wednesday'
	cnt = count < 3 ? count : 3
	ret_str << '<td></td>' * cnt
	count -= cnt
	sd += cnt.days
      when 4 # thursday
	# debug 'thursday'
	cnt = count < 2 ? count : 2
	ret_str << '<td></td>' * cnt
	count -= cnt
	sd += cnt.days
      when 5 # friday
	# debug 'friday'
	ret_str << '<td></td>' * 1
	count -= 1
	sd += 1.days
      else
	error "sd is #{sd} and count is #{count}"
      end
    end
    return ret_str
  end

  def day_count(res, this_date)
    if res.startdate > @endDate
      debug "reservation starts late #{res.startdate}"
      return 0
    elsif @startDate > res.startdate 
      startdate = @startDate 
      # debug '1'
    else
      startdate = res.startdate
      # debug '2'
    end
    if res.enddate < @endDate 
      enddate = res.enddate 
      # debug '3'
    else
      enddate = @endDate
      # debug '4'
    end
    if @option.use_closed?
      debug "day_count: use_closed.. startdate = #{res.startdate} enddate = #{res.enddate}"
      if enddate < @closedStart || startdate > @closedEnd
	# We are open just a normal count - case 1 & 2
	debug "#{enddate} < #{@closedStart} or #{startdate} > #{@closedEnd}"
	debug '1 - day_count: normal count'
        cnt = enddate - startdate
      elsif startdate < @closedStart && enddate > @closedEnd
	debug "#{startdate} < #{@closedStart} && #{enddate} > #{@closedEnd}"
        debug '2 - spanning'
	cnt = enddate - startdate - @closedDays +1
      elsif startdate >= @closedStart && enddate < @closedEnd
	debug '3 - start and end in closed'
        cnt = 0
      elsif startdate < @closedStart && enddate >= @closedStart
	debug "#{startdate} < #{@closedStart} && #{enddate} > #{@closedStart}"
	debug '4 - start before closed end in closed'
        cnt = @closedStart - startdate
      elsif startdate >= @closedStart && startdate < @closedEnd && enddate > @closedEnd
	debug '5 - start in closed and end after closed'
        cnt = enddate - @closedEnd - 1
      else
	debug "startdate #{startdate} enddate #{enddate}"
        debug '6 - how did we get here?'
	cnt = 0
      end
    else
      cnt = enddate - startdate
      cnt = cnt > 1 ? cnt : 1
    end
    debug "count for #{res.id}, #{res.camper.full_name} #{res.startdate} to #{res.enddate} is #{cnt}"
    debug "startdate is #{startdate}, enddate is #{enddate}, this_date is #{this_date}"
    return cnt
  end

  def trunc_name(cnt, res)
    name_cnt = (cnt * 2).to_i
    if res.camper.full_name.size > name_cnt
      if res.camper.last_name.size > name_cnt
	res.camper.last_name[0,name_cnt]
      else
        res.camper.last_name
      end
    else
      res.camper.full_name
    end
  end
end
