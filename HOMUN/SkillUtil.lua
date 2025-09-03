--TODO: Skills and Cooldown system

---@param currentTime number
---@param lastTime number
---@param cooldown number
function CanUseSkill(currentTime, lastTime, cooldown)
  if (currentTime - lastTime) > cooldown then
    return true
  end
  return false
end

---@param skill number
---@param cdFunc fun(level?: number): number
function RegisterSkill(skill, cdFunc)
  MyCooldown[GetV(V_HOMUNTYPE, MyID)][skill] = {
    cd = cdFunc,
    lastTime = 0,
  }
end

function CanCastSkill(skill, level)
  if not skill or level <= 0 then
    return false
  end
  local cdInfo = MyCooldown[skill]
  if not cdInfo then
    return false
  end
  return CanUseSkill(CurrentTime, cdInfo.lastTime, cdInfo.cd(level))
end

-- FIX: Not working
function MarkSkillUsed(skill)
  if MyCooldown[skill] ~= nil then
    MyCooldown[skill].lastTime = CurrentTime
  end
end

-- FIX: V_SKILLATTACKRANGE only return 1
function HasSkill(skill, level)
  local rA = GetV(V_SKILLATTACKRANGE, MyID, skill)
  if type(rA) == 'number' and rA > 1 then
    return true
  end
  local rB = GetV(V_SKILLATTACKRANGE_LEVEL, MyID, skill, level)
  if type(rB) == 'number' and rB > 1 then
    return true
  end
  return false
end

-- FIX: Undefined global functions
function SetSkills()
  if next(MyCooldown) == nil then
    if IsLif(MyID) or IsLifH(MyID) then
      RegisterSkill(HLIF_HEAL, function()
        return 20
      end)
      RegisterSkill(HLIF_AVOID, function(lv)
        return (15 + lv * 5) * 1000
      end)
      RegisterSkill(HLIF_CHANGE, function(lv)
        return 60
      end) -- ajuste teu valor real aqui
    end
    if IsAmistr(MyID) or IsAmistrH(MyID) then
      RegisterSkill(HAMI_CASTLE, function()
        return 1
      end)
      RegisterSkill(HAMI_DEFENCE, function(lv)
        return math.max(1, 45 - lv * 5)
      end)
      RegisterSkill(HAMI_BLOODLUST, function(lv)
        return 60000
      end) -- evita fórmula negativa
    end
    if IsFilir(MyID) or IsFilirH(MyID) then
      RegisterSkill(HFLI_MOON, function()
        return 2
      end)
      RegisterSkill(HFLI_FLEET, function(lv)
        return (65 + lv * 5)
      end)
      RegisterSkill(HFLI_SPEED, function(lv)
        return (65 + lv * 5)
      end)
      RegisterSkill(HFLI_SBR44, function()
        return 1000
      end)
    end
    if IsVanilmirth(MyID) or IsVanilmirthH(MyID) then
      RegisterSkill(HVAN_CAPRICE, function(lv)
        return (2 + lv * 0.2)
      end)
      RegisterSkill(HVAN_CHAOTIC, function()
        return 3000
      end)
    end
  end
end

---@param skill number
---@return number
function GetSkillLevel(skill)
  for lv = 10, 1, -1 do
    if HasSkill(skill, lv) then
      return lv
    end
  end
  return 0
end
