class Setup::DiscountController < ApplicationController
  before_filter :login_from_cookie
  before_filter :check_login
  before_filter :authorize

#####################################################
# Discounts
#####################################################
  def list
    @page_title = 'List of discounts offered'
    @discounts = Discount.all
  end

  def sort
    @page_title = 'Update sort order of discounts'
    @discounts = Discount.all
  end

  def resort
    pos = 1
    params[:discounts].each do |id|
      Discount.update(id, :position => pos)
      pos += 1
    end
    redirect_to :action => :sort
  end

  def new
    @page_title = 'Create a new discount'
    @discount = Discount.new
  end

  def create
    @discount = Discount.new(params[:discount])
    if @discount.save
      flash[:notice] = "Discount #{@discount.name} was successfully created."
      redirect_to :action => 'list'
    else
      @page_title = 'Create a new discount'
      render :new
    end
  end

  def edit
    @page_title = 'Edit a discount'
    @discount = Discount.find(params[:id])
  end

  def update
    @discount = Discount.find(params[:id])
    if @discount.update_attributes(params[:discount])
      flash[:notice] = "Discount #{@discount.name} was successfully updated."
      redirect_to :action => 'list'
    else
      @page_title = 'Edit a discount'
      render :action => :edit
    end
  end

  def destroy
    @discount = Discount.find(params[:id])
    @discount.destroy
    if @discount.errors.count.zero?
      flash[:notice] = "Discount #{@discount.name} was deleted"
    else
      debug @discount.errors.full_messages[0]
      (msg,comma,junk) = @discount.errors.full_messages[0].rpartition ','
      flash[:error] = msg + '. Recommend you change active to false.'
    end
    redirect_to :action => :list
  end

end
