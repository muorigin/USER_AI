require 'AI.USER_AI.HOMUN.Const'
require 'AI.USER_AI.HOMUN.Util'
require 'AI.USER_AI.HOMUN.CMD'
-- BEHAVIOR TREE
-- LEARN MORE: https://youtu.be/gXrKGTPwfO8?si=i-x-jRQch6dJcmjI

---@enum status
STATUS = {
  running = 1,
  success = 2,
  failure = 3,
}

---@class Node
---@field new ?fun(self: Node, children: Node[]): Node
---@field children Node[]?
---@field update fun(self: Node): status
---@field idx ?number

---AI, stop in the first failure, actions in sequence
---ENEMY -> CHASE -> ATTACK
---@type Node
local Sequence = {
  idx = 1,
  children = nil,
  update = function(self)
    while self.idx <= #self.children do
      local child = self.children[self.idx]
      local status = child:update()
      if status == STATUS.running then
        TraceAI 'SEQUENCE -> RUNNING'
        return STATUS.running
      elseif status == STATUS.failure then
        TraceAI 'SEQUENCE -> FAILURE'
        self.idx = 1
        return STATUS.failure
      else -- success
        TraceAI 'SEQUENCE -> SUCCESS -> +1'
        self.idx = self.idx + 1
      end
    end
    self.idx = 1
    TraceAI 'SEQUENCE -> SUCCESS -> 1'
    return STATUS.success
  end,
  new = function(self, children)
    local obj = {
      children = children or {},
      idx = 1,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
  end,
}

---AI, do only one action at time
---SEQUENCE | FOLLOW | PATROL | IDLE
---@type Node
local Selector = {
  idx = 1,
  new = function(self, children)
    local obj = {
      children = children or {},
      idx = 1,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
  end,
  update = function(self)
    TraceAI 'SELECTOR'
    while self.idx <= #self.children do
      local status = self.children[self.idx]:update()
      if status == STATUS.success then
        TraceAI 'SELECTOR -> SUCCESS'
        self.idx = 1
        return STATUS.success
      elseif status == STATUS.running then
        TraceAI 'SELECTOR -> RUNNING'
        return STATUS.running
      else
        TraceAI 'SELECTOR -> SUCCESS -> +1'
        self.idx = self.idx + 1
      end
    end

    self.idx = 1
    TraceAI 'SELECTOR -> FAILURE'
    return STATUS.failure
  end,
}

ResCmdList = List.new()
local CommandNode = {
  CurrentCommand = nil,
  update = function(self)
    local msg = GetMsg(MyID)
    local rmsg = GetResMsg(MyID)

    if msg[1] ~= NONE_CMD then
      List.clear(ResCmdList)
      ProcessCommand(msg)
      self.CurrentCommand = msg
    elseif rmsg[1] ~= NONE_CMD and List.size(ResCmdList) < 10 then
      List.pushright(ResCmdList, rmsg)
    end

    if not self.CurrentCommand then
      self.CurrentCommand = List.popleft(ResCmdList)
    end

    if self.CurrentCommand then
      ProcessCommand(self.CurrentCommand)
      if self.CurrentCommand[1] == MOVE_CMD then
        local x, y = self.CurrentCommand[2], self.CurrentCommand[3]
        local curX, curY = GetV(V_POSITION, MyID)
        if math.abs(curX - x) <= 1 and math.abs(curY - y) <= 1 then
          self.CurrentCommand = nil
          return STATUS.success
        else
          return STATUS.running
        end
      else
        self.CurrentCommand = nil
        return STATUS.success
      end
    end
    return STATUS.failure
  end,
}

---@type Node
local AttackEnemyNode = {
  update = function(_)
    TraceAI 'ATTACK_ENEMY'
    if MyEnemy == 0 or IsOutOfSight(MyID, MyEnemy) then
      TraceAI 'ATTACK_ENEMY -> OutOfSight'
      return STATUS.failure
    end
    if MOTION_DEAD == GetV(MOTION_DEAD, MyEnemy) then
      TraceAI 'ATTACK_ENEMY -> DEAD'
      MyEnemy = 0
      return STATUS.success
    end
    Attack(MyID, MyEnemy)
    TraceAI 'ATTACK_ENEMY -> ATTACK'
    return STATUS.running
  end,
}

---@type Node
local GetEnemyNode = {
  update = function()
    MyEnemy = GetOwnerEnemy(MyID)
    if MyEnemy == 0 or MyEnemy == -1 then
      MyEnemy = GetMyEnemy(MyID)
    end
    if MyEnemy == 0 or MyEnemy == -1 then
      return STATUS.failure
    end
    if IsOutOfSight(MyID, MyEnemy) then
      MyEnemy = 0
      return STATUS.failure
    end
    return STATUS.success
  end,
}

---@type Node
local ChaseEnemyNode = {
  update = function()
    TraceAI 'CHASE_ENEMY'
    if IsInAttackSight(MyID, MyEnemy) then
      TraceAI 'CHASE_ENEMY -> In Attack Range'
      return STATUS.success
    end
    if IsOutOfSight(MyID, MyEnemy) then
      TraceAI 'CHASE_ENEMY -> Out of Sight'
      MyEnemy = 0
      MyDestX, MyDestY = 0, 0
      return STATUS.failure
    end
    local enemyX, enemyY = GetV(V_POSITION, MyEnemy)
    if MyDestX ~= enemyX or MyDestY ~= enemyY then
      MyDestX, MyDestY = enemyX, enemyY
      Move(MyID, MyDestX, MyDestY)
      TraceAI 'CHASE_ENEMY -> RUNNING'
      return STATUS.running
    end
    TraceAI 'CHASE_ENEMY -> RUNNING'
    return STATUS.running
  end,
}

local FollowNode = {
  update = function(_)
    TraceAI 'FOLLOW'
    if GetDistanceFromOwner(MyID) >= 3 then
      TraceAI 'FOLLOW -> MoveToOwner'
      MoveToOwner(MyID)
      return STATUS.running
    end
    if IsOutOfSight(MyID, MyOwner) then
      TraceAI 'FOLLOW -> IsOutOfSight'
      return STATUS.failure
    end
    TraceAI 'FOLLOW -> SUCCESS'
    return STATUS.success
  end,
}

local IdleNode = {}
IdleNode.update = function()
  TraceAI 'IDLE'
  if GetV(V_MOTION, MyOwner) ~= MOTION_STAND then
    TraceAI 'IDLE -> OWNER DOING SOMETHING'
    return STATUS.failure
  end
  TraceAI 'IDLE -> SUCCESS'
  return STATUS.success
end

local PatrolNode = {
  update = function(_)
    TraceAI 'PATROL'
    if GetV(V_MOTION, MyOwner) ~= MOTION_SIT then
      TraceAI 'PATROL -> OWNER NOT SITTING'
      return STATUS.failure
    end
    local cooldown = math.random(10) -- x seconds
    if (CurrentTime - LastTimePatrol) > cooldown then
      local destX, destY = GetV(V_POSITION, MyOwner)
      local randomX = math.random(-10, 10)
      local randomY = math.random(-10, 10)
      destX = destX + randomX
      destY = destY + randomY
      TraceAI 'PATROL -> MOVE'
      Move(MyID, destX, destY)
      LastTimePatrol = CurrentTime
      TraceAI 'PATROL -> SUCCESS'
      return STATUS.success
    end
    TraceAI 'PATROL -> RUNNING'
    return STATUS.running
  end,
}

---@type Node
local root = Selector:new {
  IdleNode,
  PatrolNode,
  FollowNode,
}

function AI(myid)
  CurrentTime = GetTick() / 1000 -- seconds
  MyID = myid
  MyOwner = GetV(V_OWNER, myid)
  local cmdStatus = CommandNode:update()
  if cmdStatus == STATUS.running or cmdStatus == STATUS.success then
    return
  end
  local sequence = Sequence:new {
    GetEnemyNode,
    ChaseEnemyNode,
    AttackEnemyNode,
  }
  local status = sequence:update()
  if status ~= STATUS.running then
    root:update()
  end
end
