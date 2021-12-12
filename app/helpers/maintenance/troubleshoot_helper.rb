module Maintenance::TroubleshootHelper
  def safePrint(item=0)
    if item == 0
      '0'
    elsif item == nil
      'nil'
    else
      item.to_s
    end
  rescue
    'nil'
  end

  def safeSpace(sp_id)
    Space.find(sp_id).name
  rescue
    debug 'no space'
    'space not found'
  end

  def safeCamper(camper_id)
    Camper.find(camper_id).full_name
  rescue
    debug 'no camper'
    'camper not found'
  end
end
