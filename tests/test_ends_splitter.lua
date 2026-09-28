-- ES1 is red on base: a centred splitter's real tile is one tile before floor(position).
local H=require "tests.harness"
local Ends=require "logic.bp.ends"
local Grid=require "logic.bp.grid"
local function belt(id,x,y,d,flow) return {id=id,kind="belt",name="transport-belt",x=x,y=y,dir=d,flow_id=flow} end
H.test("ES1 belt into centred splitter tile is not turned",function()
    local es={belt("end",4,6,Grid.NORTH,"a"),{id="sp",kind="splitter",name="splitter",x=5,y=5,position={x=5,y=5},dir=Grid.NORTH,flow_id="a"}}
    H.equal(Ends.turn_heads({entities=es}),0)
    H.equal(es[1].dir,Grid.NORTH)
end)
io.write("ES1\n")
local function naive(es)
    local function k(e) local n=e.name or ""; if n:find("splitter",1,true) then return "splitter" elseif n:find("belt",1,true) then return "belt" end end
    local function xy(e) return math.floor(e.x),math.floor(e.y) end
    local function occupied(e,x,y)
        local a,b=xy(e); if k(e)=="splitter" then return x==a and (y==b or y==b+1) end
        return x==a and y==b
    end
    local function accepts(e,d) return k(e)=="belt" and e.dir~= (d+8)%16 or k(e)=="splitter" and e.dir==d end
    local function has(x,y,d,flow)
        for _,e in ipairs(es) do if occupied(e,x,y) and accepts(e,d) and e.flow_id~=flow then return true end end
        return false
    end
    local dx={[0]=0,[4]=1,[8]=0,[12]=-1}; local dy={[0]=-1,[4]=0,[8]=1,[12]=0}
    local function fronts(e,d,x,y) local a,b=xy(e); return d~=nil and a+dx[d]==x and b+dy[d]==y end
    local turned=0
    for _,e in ipairs(es) do if k(e)=="belt" and not e.ug_role then local d=e.dir; local x,y=xy(e)
        if has(x+dx[d],y+dy[d],d,e.flow_id) then for _,h in ipairs({(d+12)%16,(d+4)%16}) do
            local bad=has(x+dx[h],y+dy[h],h,e.flow_id)
            if not bad then for _,f in ipairs(es) do if f~=e and fronts(f,f.dir,x,y) then
                local fx,fy=xy(f)
                if fx==x+dx[h] and fy==y+dy[h] or k(f) and f.flow_id~=e.flow_id then bad=true; break end
            end end end
            if not bad then e.dir=h; turned=turned+1; break end
        end end
    end end
    return turned
end
H.test("ET1 indexed turn result matches naive scan for 5000 belts",function()
    local es={}
    es[1]=belt("b1",5,5,Grid.SOUTH,"a")
    es[2]=belt("b2",5,6,Grid.EAST,"b")
    for i=3,5000 do
        es[i]=belt("b"..i,100+i,20,Grid.EAST,"a")
        -- Keep a full 5,000-belt input while concentrating candidate heads in two active belts.
        es[i].ug_role="output"
    end
    local copy={}; for i,e in ipairs(es) do local c={}; for k,v in pairs(e) do c[k]=v end; copy[i]=c end
    local expected=naive(copy)
    local started=os.clock(); local actual=Ends.turn_heads({entities=es}); local elapsed=os.clock()-started
    H.equal(actual,expected); for i=1,#es do H.equal(es[i].dir,copy[i].dir) end
    H.equal(elapsed<=0.2,true,"turn_heads under 0.2s")
    io.write("ET1 ",string.format("%.4f",elapsed),"s\n")
end)
H.done("test_ends_splitter")
