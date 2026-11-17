-- card_art: pick one of several art variants for a card on the card detail page.
-- Variants come from "art packs": kmod/art/<pack>/index.json + PNG files (made by tools/kmod-art from patch paks).
-- The game paints a 2D card with a material (parameter "CardImage"); we swap that texture and keep the choice per card art.

local ART = kmod.paths.root .. "/art"
local DATA = kmod.paths.root .. "/data/" .. Mod.id
kmod.mkdirs(DATA)
local CHOICES = DATA .. "/choices.json"
local PARAM = "CardImage"
local CLICK = "WBP_NUI_MasterTextButton_C:BndEvt__Button_0_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature"

local packs, byAsset, choices = {}, {}, {}
local texCache, state, buttons = {}, {}, {}
local pending = {}      -- freshly created card objects waiting for their material (see the loops at the end)
local tracked = {}      -- addr -> the cards that have variants: re-checked every 50 ms (see the loops at the end)

-- ---------------------------------------------------------------- data
local function scan()
  packs, byAsset = {}, {}
  for _, e in ipairs(kmod.listdir(ART)) do
    if e.dir then
      local dir = ART .. "/" .. e.name
      local txt = kmod.readFile(dir .. "/index.json")
      local idx = txt and kmod.json.decode(txt)
      if type(idx) == "table" then
        packs[#packs + 1] = e.name
        for _, it in ipairs(idx) do
          local key = tostring(it.Asset):lower()
          byAsset[key] = byAsset[key] or {}
          table.insert(byAsset[key], { pack = e.name, file = dir .. "/" .. it.File })
        end
      end
    end
  end
  table.sort(packs)
  for _, list in pairs(byAsset) do table.sort(list, function(a, b) return a.pack < b.pack end) end
  local n = 0
  for _ in pairs(byAsset) do n = n + 1 end
  Log.info(#packs .. " art pack(s), " .. n .. " asset(s) with variants")
end

local function loadChoices()
  local txt = kmod.readFile(CHOICES)
  local t = txt and kmod.json.decode(txt)
  choices = type(t) == "table" and t or {}
end
local function saveChoices() kmod.writeFile(CHOICES, kmod.json.encode(choices)) end

-- "/Game/Assets/Textures/Images/Germany/t_pnz_35t.t_pnz_35t" -> "/game/assets/textures/images/germany/t_pnz_35t"
local function assetOf(tex)
  local p = tex:GetPathName()
  return (p:match("^(.-)%.[^./:]+$") or p):lower()
end

local lib = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
local function texture(file)
  local t = texCache[file]
  if t and t:IsValid() then return t end
  t = lib:ImportFileAsTexture2D(FindFirstOf("PlayerController"), file)
  if t:IsValid() then texCache[file] = t; return t end
  Log.warn("could not import " .. file)
end

-- ---------------------------------------------------------------- applying a variant to a 2D card
local function variantFile(asset, pack)
  for _, v in ipairs(byAsset[asset] or {}) do if v.pack == pack then return v.file end end
end

-- mat: the card's material instance (MID); orig: optional, the game's own texture for this card
local function applyMat(mat, refresh, orig, param)
  param = param or PARAM
  if not (mat and mat:IsValid()) then return end
  local cur = mat:K2_GetTextureParameterValue(param)
  local addr = mat:GetAddress()
  if orig and orig:IsValid() and orig:GetPathName():find("^/Game/") then
    local a = assetOf(orig)
    if not state[addr] or state[addr].asset ~= a then state[addr] = { asset = a, orig = orig } end
  elseif cur:IsValid() and cur:GetPathName():find("^/Game/") then           -- the game just (re)set the card's own art
    state[addr] = { asset = assetOf(cur), orig = cur }
  end
  local st = state[addr]
  if not st then return end
  if byAsset[st.asset] then tracked[addr] = { mat = mat, refresh = refresh, param = param } else tracked[addr] = nil end
  local target = st.orig
  local want = choices[st.asset]
  if want then
    local file = variantFile(st.asset, want)
    local t = file and texture(file)
    if t then target = t end
  end
  if target and target:IsValid() and not (cur:IsValid() and cur == target) then
    mat:SetTextureParameterValue(param, target)
    if refresh then refresh() end
  end
  return st.asset
end

-- a 2D card widget (detail page, lists): the material is painted by an Image widget, which must be told to repaint
local function apply(w)
  local mat = w.mat
  return applyMat(mat, function() pcall(function() w.Image:SetBrushFromMaterial(mat) end) end)
end

-- 3D card actors (collection grid, hand, battlefield): CardMaterial on the CardV2 mesh, drawn every frame
local CARD3D = { "BP_HandCardLook_C", "BP_BaseCard_C", "BP_HandCard_C", "BP_DraftingCard_C" }
local function apply3D(h)
  local ok, mat = pcall(function() return h.CardMaterial end)
  if not (ok and mat and mat:IsValid()) then return end
  local okr, ref = pcall(function() return h.imageObjectReference end)
  return applyMat(mat, nil, okr and ref or nil)
end
-- deck builder rows (W_CollectionCardDeckWidget_C): a small Image whose material has the parameter "mainImage"
local function applyRow(row)
  local im = row.thumbnailimage
  local ok, b = pcall(function() return im.Brush end)
  local mat = ok and b and b.ResourceObject
  if not (mat and mat:IsValid() and mat:GetClass():GetName() == "MaterialInstanceDynamic") then return end
  local okr, ref = pcall(function() return row.imageObjectReference end)
  return applyMat(mat, function() pcall(function() im:SetBrushFromMaterial(mat) end) end, okr and ref or nil, "mainImage")
end

local function applyAll3D()
  if next(byAsset) == nil then return end
  for _, row in ipairs(FindAllOf("W_CollectionCardDeckWidget_C") or {}) do
    local ok, err = pcall(applyRow, row)
    if not ok then Log.warn("applyRow: " .. tostring(err)) end
  end
  for _, cn in ipairs(CARD3D) do
    for _, h in ipairs(FindAllOf(cn) or {}) do
      local ok, err = pcall(apply3D, h)
      if not ok then Log.warn("apply3D: " .. tostring(err)) end
    end
  end
end

-- ---------------------------------------------------------------- the switch button on the detail page
local function variants(asset)
  local list = { "" }                                                -- "" = the game's own art
  for _, v in ipairs(byAsset[asset] or {}) do list[#list + 1] = v.pack end
  return list
end

local function label(asset)
  local cur = choices[asset]
  return Lang.t("art") .. ": " .. ((cur and cur ~= "") and cur or Lang.t("original"))
end

local function detailOf(w)
  local ok, det = pcall(function() return w:GetOuter():GetOuter() end)
  if ok and det:IsValid() and det:GetClass():GetName() == "W_CollectionCardDetail_Mobile_C" then return det end
end

local function refreshButton(det, asset)
  local b = buttons[det:GetAddress()]
  if not (b and b:IsValid()) then return end
  if asset and #variants(asset) > 1 then
    pcall(function() b:SetVisibility(0) end)
    b:SetText(label(asset))
  else
    pcall(function() b:SetVisibility(1) end)                         -- Collapsed: no variants for this card
  end
end

local function ensureButton(det)
  local addr = det:GetAddress()
  local b = buttons[addr]
  if b and b:IsValid() then return b end
  local cls = FindObject("WidgetBlueprintGeneratedClass", "WBP_NUI_MasterTextButton_C")
  local wl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
  b = wl:Create(det, cls, FindFirstOf("PlayerController"))
  det.widgetSwitcherButtonHBox:AddChild(b)
  buttons[addr] = b
  Log.info("added the art button to " .. det:GetName())
  return b
end

-- Hooks only see functions the ENGINE calls (events, delegates). Calls inside one Blueprint (like SetCardImage from the
-- detail page's own graph) never pass through ProcessEvent, so we hook the entry points instead:
--   * W_CollectionCardDetail_Mobile_C:Construct / UpdateCollectionCardVisuals : the page opens or shows another card
--   * W_Card2D_C:OnLoaded_*                                                    : the card's art finished loading (async)
local function onCard2D(w)
  local asset = apply(w)
  local det = detailOf(w)
  if det then ensureButton(det); refreshButton(det, asset) end
end
local function onDetail(det)
  ensureButton(det)
  local w = det.W_Card2D
  refreshButton(det, w and w:IsValid() and apply(w) or nil)
end

local cardCls = FindObject("WidgetBlueprintGeneratedClass", "W_Card2D_C")
local hooked = 0
for _, f in ipairs(cardCls:GetFunctions()) do
  local fn = f:match("^W_Card2D_C%.(OnLoaded_.+)$")
  if fn then
    RegisterHook("W_Card2D_C:" .. fn, function() end, function(self) Log.debug("OnLoaded"); onCard2D(self) end)
    hooked = hooked + 1
  end
end
Log.info("hooked " .. hooked .. " OnLoaded callback(s) of W_Card2D_C")
RegisterHook("W_Card2D_C:SetCardImage", function() end, function(self) onCard2D(self) end)
RegisterHook("W_CollectionCardDetail_Mobile_C:Construct", function() end, function(self) Log.debug("detail Construct"); onDetail(self) end)
RegisterHook("W_CollectionCardDetail_Mobile_C:UpdateCollectionCardVisuals", function() end, function(self) Log.debug("detail UpdateCollectionCardVisuals"); onDetail(self) end)

RegisterHook(CLICK, function() end, function(self)
  for addr, b in pairs(buttons) do
    if b:IsValid() and b == self then
      local det
      for _, d in ipairs(FindAllOf("W_CollectionCardDetail_Mobile_C") or {}) do if d:GetAddress() == addr then det = d end end
      if not det then return end
      local w = det.W_Card2D
      local st = state[w.mat:GetAddress()]
      if not st then return end
      local list = variants(st.asset)
      local cur = choices[st.asset] or ""
      local idx = 1
      for i, v in ipairs(list) do if v == cur then idx = i end end
      local nextv = list[(idx % #list) + 1]
      choices[st.asset] = (nextv ~= "") and nextv or nil
      saveChoices()
      apply(w)
      applyAll3D()
      refreshButton(det, st.asset)
      Log.info(st.asset .. " -> " .. ((nextv ~= "") and nextv or "original"))
    end
  end
end)

scan()
loadChoices()
-- The game sets a card's art inside its own graphs, which no hook can see, so we poll:
--   * every ~8 ms (FastLoop): the cards we already know have variants -- fixes a flash of the original art within a frame
--   * every second: scan all card objects for new ones
--   * when a card object is created: scan again right away (and 150 ms later)
FastLoop(8, function()                        -- runs every few ms on the game thread (core 'fast lane'), not only at 20 Hz
  for addr, t in pairs(tracked) do
    if not t.mat:IsValid() then tracked[addr] = nil
    else
      local ok, err = pcall(applyMat, t.mat, t.refresh, nil, t.param)
      if not ok then Log.warn("fast check: " .. tostring(err)); tracked[addr] = nil end
    end
  end
  -- objects created a moment ago: their material appears some hundreds of ms later (the game builds the card in its own
  -- graph), so look at each of them every 50 ms until it has one, for at most 3 s
  for i = #pending, 1, -1 do
    local p = pending[i]
    p.age = p.age + 1
    local done = true
    if p.obj:IsValid() and p.age <= 60 then
      local ok, asset = pcall(p.fn, p.obj)
      done = ok and asset ~= nil
    end
    if done then table.remove(pending, i) end
  end
  return false
end)
LoopAsync(1000, function() applyAll3D(); return false end)

local function watch(fn) return function(obj) if next(byAsset) ~= nil then pending[#pending + 1] = { obj = obj, fn = fn, age = 0 } end end end
for _, cn in ipairs(CARD3D) do NotifyOnNewObject(cn, watch(apply3D), true) end        -- true = fast scan (~60 Hz)
NotifyOnNewObject("W_CollectionCardDeckWidget_C", watch(applyRow), true)
NotifyOnNewObject("W_Card2D_C", watch(apply), true)

-- the detail page may already be open when the mod loads
for _, w in ipairs(FindAllOf("W_Card2D_C") or {}) do
  local det = detailOf(w)
  if det then
    local ok, vis = pcall(function() return w:IsVisible() end)
    if ok and vis then local asset = apply(w); ensureButton(det); refreshButton(det, asset) end
  end
end
