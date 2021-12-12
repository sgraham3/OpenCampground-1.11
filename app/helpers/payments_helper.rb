module PaymentsHelper
  def confirm_text(id)
    ct = CardTransaction.find_by_payment_id(id)
    if ct
      I18n.t('general.ConfirmDestroy') + ' It will also void or refund the associated credit card transaction.'
    else
      I18n.t('general.ConfirmDestroy')
    end
  end
end
