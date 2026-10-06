local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = Device.screen
local TextWidget = require("ui/widget/textwidget")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local _ = require("gettext")

local Trainer = WidgetContainer:extend{
    name = "schultetable",
    is_doc_only = false,
}

local SETTINGS = LuaSettings:open(DataStorage:getSettingsDir() .. "/numbersearch.lua")
local MODES = {
    classic = "Classic Schulte",
    mosaic = "Mosaic",
    rect = "Irregular Rectangles",
    scatter = "Free Scatter",
}
local COUNTS = {9, 16, 25, 36, 49}

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

local function pointInPoly(px, py, p)
    local inside = false
    local j = #p
    for i = 1, #p do
        local xi, yi = p[i].x, p[i].y
        local xj, yj = p[j].x, p[j].y
        if ((yi > py) ~= (yj > py)) and
           (px < (xj-xi) * (py-yi) / ((yj-yi) == 0 and 1e-9 or (yj-yi)) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function polygonCentroid(poly)
    local sx, sy = 0, 0
    for _, p in ipairs(poly) do sx = sx + p.x; sy = sy + p.y end
    return sx/#poly, sy/#poly
end

-- Return the distance from a point to a line segment.
local function pointSegmentDistance(px, py, a, b)
    local vx, vy = b.x-a.x, b.y-a.y
    local wx, wy = px-a.x, py-a.y
    local vv = vx*vx + vy*vy
    local t = vv > 0 and (wx*vx + wy*vy) / vv or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local qx, qy = a.x+t*vx, a.y+t*vy
    local dx, dy = px-qx, py-qy
    return math.sqrt(dx*dx + dy*dy)
end

local function distanceToPolyEdge(px, py, poly)
    local d = 1e99
    for i=1,#poly do
        local e = pointSegmentDistance(px, py, poly[i], poly[i%#poly+1])
        if e < d then d = e end
    end
    return d
end

-- Approximate the visual centre of a polygon: the interior point with the
-- greatest clearance from every edge. This keeps labels away from narrow
-- corners and outer Mosaic boundaries much better than a vertex centroid.
local function visualCenter(poly)
    local minx,miny,maxx,maxy=1e99,1e99,-1e99,-1e99
    for _,p in ipairs(poly) do
        minx=math.min(minx,p.x); miny=math.min(miny,p.y)
        maxx=math.max(maxx,p.x); maxy=math.max(maxy,p.y)
    end
    local cx,cy=polygonCentroid(poly)
    local bestx,besty,bestd=cx,cy,-1
    if pointInPoly(cx,cy,poly) then bestd=distanceToPolyEdge(cx,cy,poly) end
    -- Coarse-to-fine search is cheap at Schulte sizes (<=49 cells), and
    -- avoids an extra geometry dependency on KOReader devices.
    local bx0,by0,bx1,by1=minx,miny,maxx,maxy
    for pass=1,4 do
        local nx,ny=7,7
        for iy=0,ny-1 do for ix=0,nx-1 do
            local x=bx0+(bx1-bx0)*(ix+0.5)/nx
            local y=by0+(by1-by0)*(iy+0.5)/ny
            if pointInPoly(x,y,poly) then
                local d=distanceToPolyEdge(x,y,poly)
                if d>bestd then bestx,besty,bestd=x,y,d end
            end
        end end
        local hw=(bx1-bx0)/nx
        local hh=(by1-by0)/ny
        bx0,bx1=bestx-hw,bestx+hw
        by0,by1=besty-hh,besty+hh
    end
    return bestx,besty,math.max(1,bestd)
end

local function clipHalfPlane(poly, mx, my, nx, ny)
    local out = {}
    if #poly == 0 then return out end
    local function val(p) return (p.x-mx)*nx + (p.y-my)*ny end
    local prev = poly[#poly]
    local pv = val(prev)
    for _, cur in ipairs(poly) do
        local cv = val(cur)
        local pin, cin = pv <= 0, cv <= 0
        if pin ~= cin then
            local den = pv - cv
            local t = den == 0 and 0 or pv / den
            out[#out+1] = {x=prev.x + t*(cur.x-prev.x), y=prev.y + t*(cur.y-prev.y)}
        end
        if cin then out[#out+1] = {x=cur.x, y=cur.y} end
        prev, pv = cur, cv
    end
    return out
end

local Game = InputContainer:extend{}

function Game:init()
    self.w, self.h = Screen:getWidth(), Screen:getHeight()
    self.header_h = math.floor(self.h * 0.09)
    self.margin = math.max(18, math.floor(self.w * 0.025))
    self.back_region = {
        x = 0,
        y = 0,
        w = math.floor(self.w * 0.28),
        h = self.header_h,
    }
    self.area = {x=self.margin, y=self.header_h+self.margin, w=self.w-2*self.margin, h=self.h-self.header_h-2*self.margin}
    self.dimen = Geom:new{x=0,y=0,w=self.w,h=self.h}
    self.ges_events = { Tap = { GestureRange:new{ges="tap", range=self.dimen} } }
    self.target, self.mistakes, self.done = 1, 0, false
    self.started = self.timer_mode == "auto" and os.time() or nil
    self.numbers = {}
    for i=1,self.count do self.numbers[i]=i end
    shuffle(self.numbers)
    self:generate()
end

function Game:generate()
    if self.mode == "classic" then self:generateClassic()
    elseif self.mode == "mosaic" then self:generateMosaic()
    elseif self.mode == "rect" then self:generateRects()
    else self:generateScatter() end
end


function Game:generateClassic()
    local side = math.floor(math.sqrt(self.count) + 0.5)
    local size = math.min(self.area.w, self.area.h)
    local x0 = self.area.x + (self.area.w-size)/2
    local y0 = self.area.y + (self.area.h-size)/2
    local cw, ch = size/side, size/side
    self.cells={}
    for r=0,side-1 do
        for col=0,side-1 do
            local i=r*side+col+1
            local c={x=x0+col*cw,y=y0+r*ch,w=cw,h=ch,num=self.numbers[i]}
            c.cx,c.cy=c.x+c.w/2,c.y+c.h/2
            self.cells[#self.cells+1]=c
        end
    end
end

local function makeBoundary(area, kind)
    local poly={}
    if kind == "circle" then
        local cx,cy=area.x+area.w/2,area.y+area.h/2
        local r=math.min(area.w,area.h)*0.48
        for i=0,31 do
            local a=2*math.pi*i/32
            poly[#poly+1]={x=cx+r*math.cos(a),y=cy+r*math.sin(a)}
        end
    else
        local cx,cy=area.x+area.w/2,area.y+area.h/2
        local rx,ry=area.w*0.48,area.h*0.46
        for i=0,23 do
            local a=2*math.pi*i/24
            local jitter=0.88+math.random()*0.12
            poly[#poly+1]={x=cx+rx*jitter*math.cos(a),y=cy+ry*jitter*math.sin(a)}
        end
    end
    return poly
end

function Game:generateMosaic()
    local boundary=makeBoundary(self.area, self.mosaic_boundary or "irregular")
    local minx,miny,maxx,maxy=1e9,1e9,-1e9,-1e9
    for _,p in ipairs(boundary) do minx=math.min(minx,p.x); miny=math.min(miny,p.y); maxx=math.max(maxx,p.x); maxy=math.max(maxy,p.y) end
    local seeds={}
    local min_d=math.sqrt((maxx-minx)*(maxy-miny)/self.count)*0.52
    for i=1,self.count do
        local best
        for attempt=1,300 do
            local p={x=minx+math.random()*(maxx-minx),y=miny+math.random()*(maxy-miny)}
            if pointInPoly(p.x,p.y,boundary) then
                local ok=true
                for _,q in ipairs(seeds) do local dx,dy=p.x-q.x,p.y-q.y; if dx*dx+dy*dy<min_d*min_d then ok=false; break end end
                if ok then best=p; break end
            end
        end
        if not best then
            repeat best={x=minx+math.random()*(maxx-minx),y=miny+math.random()*(maxy-miny)} until pointInPoly(best.x,best.y,boundary)
        end
        seeds[#seeds+1]=best
    end
    self.cells={}
    for i,s in ipairs(seeds) do
        local poly={}
        for _,p in ipairs(boundary) do poly[#poly+1]={x=p.x,y=p.y} end
        for j,t in ipairs(seeds) do if i~=j then
            poly=clipHalfPlane(poly,(s.x+t.x)/2,(s.y+t.y)/2,t.x-s.x,t.y-s.y)
        end end
        local cx,cy,safe_r=visualCenter(poly)
        self.cells[#self.cells+1]={poly=poly,num=self.numbers[i],cx=cx,cy=cy,safe_r=safe_r}
    end
end

function Game:generateRects()
    local cells = {{x=self.area.x,y=self.area.y,w=self.area.w,h=self.area.h}}
    while #cells < self.count do
        local best_i, best_area = 1, 0
        for i,c in ipairs(cells) do
            if c.w*c.h > best_area then best_i,best_area=i,c.w*c.h end
        end
        local c = table.remove(cells,best_i)
        local vertical = c.w/c.h > 1.12 or (c.w/c.h > 0.88 and math.random()<0.5)
        local ratio = 0.38 + math.random()*0.24
        if vertical then
            local a = math.floor(c.w*ratio)
            cells[#cells+1]={x=c.x,y=c.y,w=a,h=c.h}
            cells[#cells+1]={x=c.x+a,y=c.y,w=c.w-a,h=c.h}
        else
            local a = math.floor(c.h*ratio)
            cells[#cells+1]={x=c.x,y=c.y,w=c.w,h=a}
            cells[#cells+1]={x=c.x,y=c.y+a,w=c.w,h=c.h-a}
        end
    end
    self.cells={}
    for i,c in ipairs(cells) do
        c.num=self.numbers[i]
        c.cx,c.cy=c.x+c.w/2,c.y+c.h/2
        self.cells[#self.cells+1]=c
    end
end

function Game:generateVoronoi()
    local seeds={}
    local min_d = math.sqrt(self.area.w*self.area.h/self.count)*0.48
    for i=1,self.count do
        local best
        for attempt=1,80 do
            local p={x=self.area.x+math.random()*self.area.w, y=self.area.y+math.random()*self.area.h}
            local ok=true
            for _,q in ipairs(seeds) do
                local dx,dy=p.x-q.x,p.y-q.y
                if dx*dx+dy*dy < min_d*min_d then ok=false; break end
            end
            if ok then best=p; break end
        end
        seeds[#seeds+1]=best or {x=self.area.x+math.random()*self.area.w,y=self.area.y+math.random()*self.area.h}
    end
    self.cells={}
    local bounds={{x=self.area.x,y=self.area.y},{x=self.area.x+self.area.w,y=self.area.y},{x=self.area.x+self.area.w,y=self.area.y+self.area.h},{x=self.area.x,y=self.area.y+self.area.h}}
    for i,s in ipairs(seeds) do
        local poly={}
        for _,p in ipairs(bounds) do poly[#poly+1]={x=p.x,y=p.y} end
        for j,t in ipairs(seeds) do if i~=j then
            local mx,my=(s.x+t.x)/2,(s.y+t.y)/2
            poly=clipHalfPlane(poly,mx,my,t.x-s.x,t.y-s.y)
        end end
        local cx,cy=polygonCentroid(poly)
        self.cells[#self.cells+1]={poly=poly,num=self.numbers[i],cx=cx,cy=cy}
    end
end

function Game:generateScatter()
    self.cells={}
    local spacing = math.sqrt(self.area.w*self.area.h/self.count)*0.60
    for i=1,self.count do
        local p
        for attempt=1,200 do
            local q={x=self.area.x+spacing/2+math.random()*math.max(1,self.area.w-spacing), y=self.area.y+spacing/2+math.random()*math.max(1,self.area.h-spacing)}
            local ok=true
            for _,c in ipairs(self.cells) do
                local dx,dy=q.x-c.cx,q.y-c.cy
                if dx*dx+dy*dy < spacing*spacing then ok=false; break end
            end
            if ok then p=q; break end
        end
        p=p or {x=self.area.x+math.random()*self.area.w,y=self.area.y+math.random()*self.area.h}
        self.cells[#self.cells+1]={num=self.numbers[i],cx=p.x,cy=p.y,r=math.max(28,spacing*0.42)}
    end
end

function Game:drawCentered(bb, text, cx, cy, size, color)
    local font_name = self.number_font or "cfont"
    local tw=TextWidget:new{text=tostring(text),face=Font:getFace(font_name,size) or Font:getFace("cfont",size),fgcolor=color or Blitbuffer.COLOR_BLACK,bold=true}
    local s=tw:getSize()
    local tx, ty = math.floor(cx-s.w/2), math.floor(cy-s.h/2)
    tw:paintTo(bb, tx, ty)
    tw:free()
    return s, tx, ty
end

function Game:paintTo(bb,x,y)
    bb:paintRect(0,0,self.w,self.h,Blitbuffer.COLOR_WHITE)
    local title = self.done and "Complete" or ("Find  "..self.target)
    local header_font = math.max(24,math.floor(self.w/24))
    self:drawCentered(bb,title,self.w/2,self.header_h/2,header_font)

    -- Native-style, borderless back control in the upper-left header.
    -- The whole left portion of the header is tappable for e-ink usability.
    local back_font = math.max(22, math.floor(self.w/30))
    self:drawCentered(
        bb,
        "‹  Back",
        self.back_region.x + self.back_region.w/2,
        self.header_h/2,
        back_font
    )

    local line=math.max(2,Screen:scaleBySize(1))
    bb:paintRect(0,self.header_h-line,self.w,line,Blitbuffer.COLOR_BLACK)
    local font_size = math.max(22, math.floor(math.min(self.w,self.h)/math.sqrt(self.count)/5.0))

    -- Classic Schulte: draw the grid once instead of drawing a border around
    -- every cell. This keeps every internal separator a single line.
    if self.mode=="classic" and #self.cells > 0 then
        local side = math.floor(math.sqrt(self.count) + 0.5)
        local first = self.cells[1]
        local x0, y0 = math.floor(first.x), math.floor(first.y)
        local grid_w = math.floor(first.w * side)
        local grid_h = math.floor(first.h * side)

        bb:paintBorder(x0, y0, grid_w, grid_h, line, Blitbuffer.COLOR_BLACK)

        for i=1,side-1 do
            local gx = math.floor(first.x + first.w * i)
            local gy = math.floor(first.y + first.h * i)
            bb:paintRect(gx, y0, line, grid_h, Blitbuffer.COLOR_BLACK)
            bb:paintRect(x0, gy, grid_w, line, Blitbuffer.COLOR_BLACK)
        end
    end

    for _,c in ipairs(self.cells) do
        local found = c.num < self.target
        if self.mode=="rect" then
            bb:paintBorder(math.floor(c.x),math.floor(c.y),math.floor(c.w),math.floor(c.h),line,Blitbuffer.COLOR_BLACK)
        elseif self.mode=="mosaic" then
            for i=1,#c.poly do
                local a,b=c.poly[i],c.poly[i%#c.poly+1]
                local dx,dy=b.x-a.x,b.y-a.y
                local steps=math.max(math.abs(dx),math.abs(dy))
                if steps>0 then for k=0,steps do
                    local px=math.floor(a.x+dx*k/steps); local py=math.floor(a.y+dy*k/steps)
                    bb:paintRect(px,py,line,line,Blitbuffer.COLOR_BLACK)
                end end
            end
        end
        local cell_font_size = font_size
        if self.mode=="mosaic" and c.safe_r then
            -- Reserve visible whitespace around the actual label. Two-digit
            -- labels need more horizontal room than single digits.
            local width_factor = c.num >= 10 and 0.72 or 0.52
            local by_width = math.floor((c.safe_r * 0.78) / width_factor)
            local by_height = math.floor(c.safe_r * 1.32)
            cell_font_size = math.max(16, math.min(font_size, by_width, by_height))
        end
        if not found or self.hard_mode then
            local numcolor=Blitbuffer.COLOR_BLACK
            local label_size, label_x, label_y = self:drawCentered(bb,c.num,c.cx,c.cy,cell_font_size,numcolor)
            if self.highlight_one and self.target==1 and c.num==1 then
                -- Highlight the starting number without enclosing it: draw a
                -- short underline matched to the actual rendered glyph width.
                local underline_h = math.max(2, Screen:scaleBySize(1))
                local gap = math.max(2, math.floor(cell_font_size * 0.08))
                local uy = math.floor(label_y + label_size.h + gap)
                bb:paintRect(label_x, uy, label_size.w, underline_h, Blitbuffer.COLOR_BLACK)
            end
        else
            self:drawCentered(bb,"·",c.cx,c.cy,cell_font_size,Blitbuffer.COLOR_GRAY)
        end
    end
end

function Game:hitCell(px,py)
    if self.mode=="rect" or self.mode=="classic" then
        for _,c in ipairs(self.cells) do if px>=c.x and px<=c.x+c.w and py>=c.y and py<=c.y+c.h then return c end end
    elseif self.mode=="mosaic" then
        for _,c in ipairs(self.cells) do if pointInPoly(px,py,c.poly) then return c end end
    else
        local best,bd=nil,1e99
        for _,c in ipairs(self.cells) do local dx,dy=px-c.cx,py-c.cy; local d=dx*dx+dy*dy; if d<bd then best,bd=c,d end end
        if best and bd <= best.r*best.r then return best end
    end
end

function Game:onTap(_,ges)
    if self.done then return true end

    local px, py = ges.pos.x, ges.pos.y
    local br = self.back_region
    if px >= br.x and px <= br.x + br.w and py >= br.y and py <= br.y + br.h then
        local game = self
        UIManager:close(game)
        game.owner:showModeDialog()
        return true
    end

    local c=self:hitCell(px,py)
    if not c then return true end
    if c.num==self.target then
        if self.target == 1 and not self.started then self.started = os.time() end
        self.target=self.target+1
        if self.target>self.count then self:finish() else UIManager:setDirty(self,"ui") end
    elseif c.num>=self.target then
        self.mistakes=self.mistakes+1
        UIManager:setDirty(self,"ui")
    end
    return true
end

function Game:finish()
    self.done=true
    local elapsed=os.time()-(self.started or os.time())
    local key=self.mode.."_"..self.count.."_"..(self.timer_mode or "auto").."_"..(self.hard_mode and "hard" or "normal")
    local best=SETTINGS:readSetting("best_"..key)
    local is_best=not best or elapsed<best
    if is_best then SETTINGS:saveSetting("best_"..key,elapsed); best=elapsed end

    local history=SETTINGS:readSetting("history") or {}
    table.insert(history, 1, {
        timestamp=os.time(), mode=self.mode, count=self.count, elapsed=elapsed,
        mistakes=self.mistakes, timer_mode=self.timer_mode or "auto",
        mosaic_boundary=self.mode=="mosaic" and (self.mosaic_boundary or "irregular") or nil,
        highlight_one=self.highlight_one and true or false,
        number_font=self.number_font or "cfont",
        hard_mode=self.hard_mode and true or false,
    })
    while #history > 50 do table.remove(history) end
    SETTINGS:saveSetting("history",history)
    SETTINGS:flush()
    UIManager:setDirty(self,"full")
    local msg=string.format("Time: %d s\nMistakes: %d\nAverage: %.2f s / number\nBest: %d s%s",elapsed,self.mistakes,elapsed/self.count,best,is_best and "  ★" or "")
    local game = self
    local finish_dialog
    finish_dialog = ButtonDialog:new{
        title="Finished — "..MODES[self.mode],
        buttons={
            {{text="Same mode again",callback=function()
                UIManager:close(finish_dialog)
                UIManager:close(game)
                game.owner:startGame(game.mode,game.count)
            end}},
            {{text="Change mode",callback=function()
                UIManager:close(finish_dialog)
                UIManager:close(game)
                game.owner:showModeDialog()
            end}},
            {{text="Close",callback=function()
                UIManager:close(finish_dialog)
                UIManager:close(game)
            end}},
        },
        info=msg,
    }
    UIManager:show(finish_dialog)
end

function Game:onClose()
    UIManager:close(self)
    return true
end

function Game:onCloseWidget()
    UIManager:setDirty(nil,"full")
end

function Trainer:init()
    math.randomseed(os.time())
    self.ui.menu:registerToMainMenu(self)
end

function Trainer:addToMainMenu(menu_items)
    menu_items.schulte_table={
        text=_("Schulte Table"),
        sorting_hint="tools",
        callback=function() self:showModeDialog() end,
    }
end

function Trainer:showModeDialog()
    local dlg
    dlg=ButtonDialog:new{title="Choose layout",buttons={
        {{text=MODES.classic,callback=function() UIManager:close(dlg); self:showCountDialog("classic") end}},
        {{text=MODES.mosaic,callback=function() UIManager:close(dlg); self:showCountDialog("mosaic") end}},
        {{text=MODES.rect,callback=function() UIManager:close(dlg); self:showCountDialog("rect") end}},
        {{text=MODES.scatter,callback=function() UIManager:close(dlg); self:showCountDialog("scatter") end}},
        {{text="Settings",callback=function() UIManager:close(dlg); self:showSettingsDialog() end}},
        {{text="Stats",callback=function() UIManager:close(dlg); self:showStatsDialog() end}},
    }}
    UIManager:show(dlg)
end

function Trainer:showSettingsDialog()
    local dlg
    local boundary=SETTINGS:readSetting("mosaic_boundary") or "irregular"
    local highlight=SETTINGS:readSetting("highlight_one") or false
    local timer_mode=SETTINGS:readSetting("timer_mode") or "auto"
    local number_font=SETTINGS:readSetting("number_font") or "cfont"
    local hard_mode=SETTINGS:readSetting("hard_mode") or false
    local font_labels={cfont="KOReader UI", ["NotoSans-Regular.ttf"]="Sans-serif", ["NotoSerif-Regular.ttf"]="Serif", ["DroidSansMono.ttf"]="Monospace"}
    dlg=ButtonDialog:new{title="Settings",buttons={
        {{text="Mosaic boundary: "..(boundary=="circle" and "Circle" or "Irregular"),callback=function()
            boundary=(boundary=="circle") and "irregular" or "circle"
            SETTINGS:saveSetting("mosaic_boundary",boundary); SETTINGS:flush(); UIManager:close(dlg); self:showSettingsDialog()
        end}},
        {{text="Highlight 1: "..(highlight and "On" or "Off"),callback=function()
            highlight=not highlight; SETTINGS:saveSetting("highlight_one",highlight); SETTINGS:flush(); UIManager:close(dlg); self:showSettingsDialog()
        end}},
        {{text="Timer: "..(timer_mode=="click1" and "Start on 1" or "Auto start"),callback=function()
            timer_mode=(timer_mode=="click1") and "auto" or "click1"
            SETTINGS:saveSetting("timer_mode",timer_mode); SETTINGS:flush(); UIManager:close(dlg); self:showSettingsDialog()
        end}},
        {{text="Number font: "..(font_labels[number_font] or "KOReader UI"),callback=function()
            local order={"cfont","NotoSans-Regular.ttf","NotoSerif-Regular.ttf","DroidSansMono.ttf"}
            local idx=1
            for i,v in ipairs(order) do if v==number_font then idx=i; break end end
            number_font=order[idx % #order + 1]
            SETTINGS:saveSetting("number_font",number_font); SETTINGS:flush(); UIManager:close(dlg); self:showSettingsDialog()
        end}},
        {{text="Hard mode: "..(hard_mode and "On" or "Off"),callback=function()
            hard_mode=not hard_mode
            SETTINGS:saveSetting("hard_mode",hard_mode); SETTINGS:flush(); UIManager:close(dlg); self:showSettingsDialog()
        end}},
        {{text="Back",callback=function() UIManager:close(dlg); self:showModeDialog() end}},
    }}
    UIManager:show(dlg)
end

function Trainer:showStatsDialog()
    local history=SETTINGS:readSetting("history") or {}
    local lines={}
    if #history == 0 then
        lines[1]="No completed games yet."
    else
        for i=1,math.min(#history,20) do
            local h=history[i]
            local date=os.date("%Y-%m-%d %H:%M",h.timestamp or os.time())
            local timer=(h.timer_mode=="click1") and "on 1" or "auto"
            local font_labels={cfont="KOReader UI", ["NotoSans-Regular.ttf"]="Sans-serif", ["NotoSerif-Regular.ttf"]="Serif", ["DroidSansMono.ttf"]="Monospace"}
            local settings="Timer: "..timer.."; Highlight 1: "..(h.highlight_one and "On" or "Off").."; Hard mode: "..(h.hard_mode and "On" or "Off").."; Font: "..(font_labels[h.number_font or "cfont"] or "KOReader UI")
            if h.mode=="mosaic" then settings=settings.."; Boundary: "..((h.mosaic_boundary=="circle") and "Circle" or "Irregular") end
            lines[#lines+1]=string.format("%d. %s  %s · %d\n   %d s · %d mistakes · %s",i,date,MODES[h.mode] or h.mode,h.count or 0,h.elapsed or 0,h.mistakes or 0,settings)
        end
    end
    local viewer
    viewer=TextViewer:new{
        title="Statistics: History",
        text=table.concat(lines,"\n\n"),
        text_type="general",
        alignment="left",
        add_default_buttons=true,
        close_callback=function() self:showModeDialog() end,
    }
    UIManager:show(viewer)
end

function Trainer:showCountDialog(mode)
    local dlg
    local rows={}
    for _,n in ipairs(COUNTS) do
        rows[#rows+1]={{text=tostring(n).." numbers",callback=function() UIManager:close(dlg); self:startGame(mode,n) end}}
    end
    rows[#rows+1]={{text="Back",callback=function() UIManager:close(dlg); self:showModeDialog() end}}
    dlg=ButtonDialog:new{title=MODES[mode].." — difficulty",buttons=rows}
    UIManager:show(dlg)
end

function Trainer:startGame(mode,count)
    SETTINGS:saveSetting("last_mode",mode); SETTINGS:saveSetting("last_count",count); SETTINGS:flush()
    local game=Game:new{mode=mode,count=count,owner=self,mosaic_boundary=SETTINGS:readSetting("mosaic_boundary") or "irregular",highlight_one=SETTINGS:readSetting("highlight_one") or false,timer_mode=SETTINGS:readSetting("timer_mode") or "auto",number_font=SETTINGS:readSetting("number_font") or "cfont",hard_mode=SETTINGS:readSetting("hard_mode") or false}
    UIManager:show(game)
    UIManager:setDirty(game,"full")
end

return Trainer
