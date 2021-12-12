require 'test_helper'

class CardTransactionTest < ActiveSupport::TestCase
  def setup
  end


  def test_account
    @ct = CardTransaction.new :process_mode => CardTransaction::TokenLocal, :cvv2 => '123'
    assert !@ct.valid?
    @ct.account = '12345678'
    assert @ct.valid?
  end
    
  def test_expiry
    @ct = CardTransaction.new :process_mode => CardTransaction::TokenLocal, :account => '9876', :cvv2 => '123'
    # valid with no expiry..Can create empty record
    assert @ct.valid?
    # valid
    @ct.expiry = Date.today.strftime("%m%y")
    assert @ct.valid?
    # real old
    @ct.expiry = '1105'
    assert !@ct.valid?
    # expired last month
    @ct.expiry = (Date.today - 1.month).strftime("%m%y")
    assert !@ct.valid?
  end

  def test_cvv2
    int = Integration.first_or_create
    int.update_attribute :cc_use_cvv, false
    @ct = CardTransaction.new :process_mode => CardTransaction::TermCard, :account => '9876'
    # not validating cvv
    assert @ct.valid?
    int.update_attribute :cc_use_cvv, true
    # validating cvv
    # valid 3 digit
    @ct.cvv2 = '123'
    assert @ct.valid?
    # valid 4 digit
    @ct.cvv2 = '1234'
    assert @ct.valid?
    # invalid 2 digit
    @ct.cvv2 = '12'
    assert !@ct.valid?
    # invalid alpha
    @ct.cvv2 = '1a34'
    assert !@ct.valid?
  end

end
